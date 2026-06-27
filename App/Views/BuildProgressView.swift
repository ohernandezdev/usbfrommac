import SwiftUI

/// Paso 4: progreso por fases, y el resultado final (éxito / error / cancelado).
struct BuildProgressView: View {
    @ObservedObject var coordinator: BuildCoordinator

    private var phase: BuildPhase { coordinator.progress.phase }

    var body: some View {
        switch phase {
        case .done:
            successView
        case .failed(let m):
            resultView(icon: "xmark.octagon.fill", color: Carbon.error,
                       title: "result.failed.title", message: Text(verbatim: m))
        case .cancelled:
            resultView(icon: "stop.circle.fill", color: Carbon.warning,
                       title: "result.cancelled.title", message: Text("result.cancelled.message"))
        default:
            runningView
        }
    }

    // MARK: En curso

    private var runningView: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            Text("progress.creating").carbon(.displayMd)

            ProgressView(value: coordinator.progress.overallFraction).tint(Carbon.primary)
            Text(verbatim: coordinator.progress.detail).carbon(.bodySm).foregroundStyle(Carbon.inkMuted)

            VStack(alignment: .leading, spacing: Carbon.Space.sm) {
                ForEach(Array(BuildPhase.ordered.enumerated()), id: \.offset) { _, p in
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
                    .disabled(!coordinator.isBuilding)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    // MARK: Éxito

    private var successView: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            HStack(spacing: Carbon.Space.xs) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Carbon.success).font(.title)
                Text("success.title").carbon(.headline).foregroundStyle(Carbon.ink)
            }
            Text("success.subtitle")
                .carbon(.body).foregroundStyle(Carbon.inkMuted)

            VStack(alignment: .leading, spacing: Carbon.Space.sm) {
                Text("success.boot.title").carbon(.bodyEmphasis)
                bootTip("success.boot.tip1")
                bootTip("success.boot.tip2")
                bootTip("success.boot.tip3")
                bootTip("success.boot.tip4")
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

    // MARK: Resultado (error / cancelado)

    private func resultView(icon: String, color: Color, title: LocalizedStringKey, message: Text) -> some View {
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
                Spacer()
                Button("common.restart") { coordinator.reset() }
                    .buttonStyle(CarbonButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    // MARK: Filas de fase

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

    /// Detalle en vivo de la fase activa: barra + métricas reales, o heartbeat
    /// (tiempo transcurrido) para fases sin sub-progreso como Formatear.
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

    /// Línea con "latido": el tiempo transcurrido avanza solo aunque la fase no
    /// reporte sub-progreso, para que NO parezca congelada.
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
        guard let current = BuildPhase.ordered.firstIndex(of: phase),
              let idx = BuildPhase.ordered.firstIndex(of: p) else {
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
