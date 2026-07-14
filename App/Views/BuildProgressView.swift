import SwiftUI
import AppKit

/// Step 4: per-phase progress, and the final result (success / error / cancelled).
struct BuildProgressView: View {
    @ObservedObject var coordinator: BuildCoordinator

    private var phase: BuildPhase { coordinator.progress.phase }

    var body: some View {
        switch phase {
        case .done:
            successView
        case .failed(let m):
            resultView(icon: "xmark.octagon.fill", color: Carbon.error,
                       title: "result.failed.title", message: Text(verbatim: m),
                       recovery: Self.recoveryAction(for: m))
        case .cancelled:
            resultView(icon: "stop.circle.fill", color: Carbon.warning,
                       title: "result.cancelled.title", message: Text("result.cancelled.message"))
        default:
            runningView
        }
    }

    // MARK: In progress

    private var runningView: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            Text("progress.creating").carbon(.displayMd)

            ProgressView(value: coordinator.progress.overallFraction).tint(Carbon.primary)
            Text(verbatim: coordinator.progress.detail).carbon(.bodySm).foregroundStyle(Carbon.inkMuted)

            VStack(alignment: .leading, spacing: Carbon.Space.sm) {
                ForEach(Array(coordinator.activePhases.enumerated()), id: \.offset) { _, p in
                    phaseRow(p)
                }
            }
            .carbonCard()

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("common.cancel") { coordinator.cancel() }
                    .buttonStyle(CarbonButton(kind: .tertiary))
                    // The raw dd is not interruptible → it can't be cancelled midway.
                    .disabled(!coordinator.isBuilding || coordinator.progress.phase == .writingImage)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    // MARK: Success

    private var successView: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            HStack(spacing: Carbon.Space.xs) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Carbon.success).font(.title)
                Text(coordinator.isRawFlow ? "success.title.linux" : "success.title.windows")
                    .carbon(.headline).foregroundStyle(Carbon.ink)
            }
            Text("success.subtitle")
                .carbon(.body).foregroundStyle(Carbon.inkMuted)

            VStack(alignment: .leading, spacing: Carbon.Space.sm) {
                Text("success.boot.title").carbon(.bodyEmphasis)
                bootTip("success.boot.tip1")
                bootTip("success.boot.tip2")
                bootTip("success.boot.tip3")
                bootTip(coordinator.isRawFlow ? "success.boot.tip4.linux" : "success.boot.tip4.windows")
            }
            .carbonCard(surface: Carbon.surface1)

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("success.createAnother") { coordinator.reset() }
                    .buttonStyle(CarbonButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    // MARK: Result (error / cancelled)

    /// A recognized failure that the app can help resolve directly, instead of just
    /// describing it in text and leaving the user to find the fix themselves.
    struct RecoveryAction {
        let label: LocalizedStringKey
        let perform: () -> Void
    }

    /// Recognizes the helper's "needs Full Disk Access" failure (raw write of a Linux
    /// ISO reading from a TCC-protected folder) and offers a button straight to the
    /// exact Settings pane, rather than making the user read the message and
    /// navigate there themselves. The helper's error strings are always English
    /// (it's a minimal daemon with no localization of its own), so matching on the
    /// English substring is reliable regardless of the app's current language.
    private static func recoveryAction(for message: String) -> RecoveryAction? {
        guard message.contains("Full Disk Access") else { return nil }
        return RecoveryAction(label: "action.openFullDiskAccess") {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func resultView(icon: String, color: Color, title: LocalizedStringKey, message: Text,
                            recovery: RecoveryAction? = nil) -> some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            HStack(spacing: Carbon.Space.xs) {
                Image(systemName: icon).foregroundStyle(color).font(.title)
                Text(title).carbon(.headline).foregroundStyle(Carbon.ink)
            }
            message.carbon(.body).foregroundStyle(Carbon.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if let recovery {
                    Button(recovery.label, action: recovery.perform)
                        .buttonStyle(CarbonButton(kind: .secondary))
                }
                Spacer()
                Button("common.restart") { coordinator.reset() }
                    .buttonStyle(CarbonButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    // MARK: Phase rows

    private func phaseRow(_ p: BuildPhase) -> some View {
        let state = phaseState(p)
        return VStack(alignment: .leading, spacing: Carbon.Space.xs) {
            HStack(spacing: Carbon.Space.sm) {
                switch state {
                case .done:    Image(systemName: "checkmark.circle.fill").foregroundStyle(Carbon.success)
                case .active:  ProgressView().controlSize(.small)
                case .pending: Image(systemName: "circle").foregroundStyle(Carbon.inkSubtle)
                }
                Text(p.title).carbon(.body)
                    .foregroundStyle(state == .pending ? Carbon.inkSubtle : Carbon.ink)
                Spacer()
                if state == .active, coordinator.progress.hasByteMetrics {
                    Text(ProgressFormatter.percent(coordinator.progress.phaseFraction))
                        .carbon(.bodySm).monospacedDigit().foregroundStyle(Carbon.inkMuted)
                }
            }
            if state == .active { activeDetail(p) }
        }
    }

    /// Live detail of the active phase: bar + real metrics, or heartbeat
    /// (elapsed time) for phases without sub-progress like Formatting.
    @ViewBuilder
    private func activeDetail(_ p: BuildPhase) -> some View {
        let prog = coordinator.progress
        if prog.hasByteMetrics, let done = prog.bytesDone, let total = prog.bytesTotal {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: prog.phaseFraction).tint(Carbon.primary)
                Text(ProgressFormatter.transferLine(done: done, total: total,
                                                     bytesPerSecond: prog.bytesPerSecond))
                    .carbon(.bodySm).monospacedDigit().foregroundStyle(Carbon.inkMuted)
            }
            .padding(.leading, Carbon.Space.lg)
        } else if p == .formatting {
            heartbeatRow(label: String(localized: "progress.heartbeat.formatting"))
        } else {
            heartbeatRow(label: String(localized: "progress.heartbeat.working"))
        }
    }

    /// Line with a "heartbeat": the elapsed time keeps advancing on its own even
    /// when the phase reports no sub-progress, so it does NOT look frozen.
    private func heartbeatRow(label: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let start = coordinator.phaseStartedAt ?? context.date
            let elapsed = max(0, context.date.timeIntervalSince(start))
            Text(verbatim: "\(label) (\(ProgressFormatter.duration(elapsed)))")
                .carbon(.bodySm).monospacedDigit().foregroundStyle(Carbon.inkMuted)
                .padding(.leading, Carbon.Space.lg)
        }
    }

    private enum PhaseState { case done, active, pending }

    private func phaseState(_ p: BuildPhase) -> PhaseState {
        let phases = coordinator.activePhases
        guard let current = phases.firstIndex(of: phase),
              let idx = phases.firstIndex(of: p) else {
            return phase == .done ? .done : .pending
        }
        if idx < current { return .done }
        if idx == current { return .active }
        return .pending
    }

    private func bootTip(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Carbon.Space.xs) {
            Image(systemName: "arrow.right").foregroundStyle(Carbon.primary).font(.caption)
            Text(text).carbon(.bodySm).foregroundStyle(Carbon.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
