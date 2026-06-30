import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Step 1: select the Windows 11 ISO and (optionally) verify its SHA-256.
struct ISOPickerView: View {
    @ObservedObject var coordinator: BuildCoordinator
    @State private var showImporter = false
    @State private var dropTargeted = false

    private var isoTypes: [UTType] {
        var types: [UTType] = [.diskImage, .data]
        if let iso = UTType(filenameExtension: "iso") { types.insert(iso, at: 0) }
        return types
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Carbon.Space.lg) {
                VStack(alignment: .leading, spacing: Carbon.Space.xs) {
                    Text("iso.title").carbon(.displayMd)
                    Text("iso.subtitle")
                        .carbon(.bodyLg).foregroundStyle(Carbon.inkMuted)
                }

                if let info = coordinator.isoInfo {
                    selectedFileBar
                    isoSummary(info)
                    hashSection
                } else {
                    dropZone
                    if let error = coordinator.isoError {
                        statusRow("exclamationmark.triangle.fill", verbatim: error, Carbon.error)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: isoTypes) { result in
            if case .success(let url) = result { coordinator.selectISO(url) }
        }
    }

    // MARK: Drop zone (drag or click)

    private var dropZone: some View {
        Button { showImporter = true } label: {
            VStack(spacing: Carbon.Space.md) {
                ZStack {
                    Circle().fill(Carbon.primary.opacity(dropTargeted ? 0.18 : 0.10))
                        .frame(width: 72, height: 72)
                    if coordinator.isInspectingISO {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Carbon.primary)
                    }
                }
                VStack(spacing: 4) {
                    Text(coordinator.isInspectingISO ? "iso.analyzing" : "iso.drop.title")
                        .carbon(.cardTitle).foregroundStyle(Carbon.ink)
                    Text("iso.drop.subtitle")
                        .carbon(.bodySm).foregroundStyle(Carbon.inkSubtle)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .background(dropTargeted ? Carbon.primary.opacity(0.06) : Carbon.surface1)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous)
                    .strokeBorder(dropTargeted ? Carbon.primary : Carbon.hairlineStrong,
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1.5, dash: [7, 6]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .animation(Carbon.Motion.fast, value: dropTargeted)
        .animation(Carbon.Motion.fast, value: coordinator.isInspectingISO)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSURL.self) { obj, _ in
                if let url = obj as? URL {
                    DispatchQueue.main.async { coordinator.selectISO(url) }
                }
            }
            return true
        }
    }

    // MARK: Selected file bar

    private var selectedFileBar: some View {
        HStack(spacing: Carbon.Space.sm) {
            Image(systemName: "opticaldisc.fill").font(.system(size: 18)).foregroundStyle(Carbon.primary)
            Text(coordinator.isoURL?.lastPathComponent ?? "")
                .carbon(.bodyEmphasis).foregroundStyle(Carbon.ink)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("iso.change") { showImporter = true }
                .buttonStyle(CarbonButton(kind: .ghost))
        }
        .padding(.vertical, Carbon.Space.xs)
        .padding(.horizontal, Carbon.Space.md)
        .background(Carbon.surface1)
        .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Carbon.Radius.control, style: .continuous).stroke(Carbon.hairline, lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("common.continue") { coordinator.goToDiskSelection() }
                .buttonStyle(CarbonButton(kind: .primary))
                .disabled(!coordinator.canProceedFromISO)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, Carbon.Space.sm)
        .background(Carbon.canvas)
    }

    @ViewBuilder
    private func isoSummary(_ info: ISOInfo) -> some View {
        VStack(alignment: .leading, spacing: Carbon.Space.sm) {
            // Detected boot type → determines the strategy (copy vs. raw).
            switch info.bootType {
            case .windows:
                statusRow("checkmark.seal.fill", "iso.type.windows", Carbon.success)
            case .hybridRaw:
                statusRow("checkmark.seal.fill", "iso.type.linux", Carbon.success)
            case .elToritoOnly, .notBootable:
                statusRow("xmark.octagon.fill", "iso.type.unsupported", Carbon.error)
            }

            // The install.wim and Secure Boot detail only applies to the Windows flow.
            if info.bootType == .windows {
                if let wim = info.installWIMSizeBytes {
                    let txt = ByteCountFormatter.string(fromByteCount: Int64(wim), countStyle: .file)
                    statusRow("doc.fill",
                              verbatim: info.requiresWIMSplit
                                  ? String(localized: "iso.wim.willSplit \(txt)")
                                  : String(localized: "iso.wim.fits \(txt)"),
                              Carbon.inkMuted)
                }
                secureBootRow(info.secureBootConcern)
            }
        }
        .carbonCard()
    }

    @ViewBuilder
    private func secureBootRow(_ concern: SecureBootConcern) -> some View {
        switch concern {
        case .likelyModern:
            statusRow("lock.shield.fill", "iso.secureBoot.modern", Carbon.success)
        case .possiblyOutdated:
            statusRow("exclamationmark.shield.fill", "iso.secureBoot.outdated", Carbon.warning)
        case .unknown:
            statusRow("questionmark.circle", "iso.secureBoot.unknown", Carbon.inkSubtle)
        }
    }

    @ViewBuilder
    private var hashSection: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.sm) {
            HStack {
                Text("hash.title").carbon(.cardTitle)
                Spacer()
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        coordinator.expectedHash = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label("hash.paste", systemImage: "clipboard")
                }
                .buttonStyle(CarbonButton(kind: .ghost))
            }
            Text("hash.subtitle")
                .carbon(.bodySm).foregroundStyle(Carbon.inkSubtle)

            CarbonTextField(placeholder: "hash.placeholder",
                            text: $coordinator.expectedHash, monospaced: true)

            // Automatic status: computed and compared only once a complete hash is detected.
            if coordinator.isHashing {
                HStack(spacing: Carbon.Space.xs) {
                    ProgressView(value: coordinator.hashProgress).tint(Carbon.primary)
                    Text("hash.computing \(Int(coordinator.hashProgress * 100))")
                        .carbon(.caption).monospacedDigit().foregroundStyle(Carbon.inkMuted)
                        .fixedSize()
                }
            } else if let matches = coordinator.hashMatches {
                statusRow(matches ? "checkmark.circle.fill" : "xmark.octagon.fill",
                          matches ? "hash.match" : "hash.noMatch",
                          matches ? Carbon.success : Carbon.error)
            }
        }
        .carbonCard()
        .onChange(of: coordinator.expectedHash) { value in
            // Automatic verification as soon as the text is a valid SHA-256 (64 hex).
            let n = ISOService.normalizedHash(value)
            if n.count == 64, n.allSatisfy(\.isHexDigit), !coordinator.isHashing {
                coordinator.verifyHash()
            }
        }
    }

    private func statusRow(_ icon: String, _ text: LocalizedStringKey, _ color: Color) -> some View {
        statusRow(icon, Text(text), color)
    }

    /// Variant for text already resolved at runtime (errors, sizes).
    private func statusRow(_ icon: String, verbatim text: String, _ color: Color) -> some View {
        statusRow(icon, Text(verbatim: text), color)
    }

    private func statusRow(_ icon: String, _ text: Text, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: Carbon.Space.xs) {
            Image(systemName: icon).foregroundStyle(color)
            text.carbon(.bodySm).foregroundStyle(Carbon.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
