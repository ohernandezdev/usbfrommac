import SwiftUI

/// Step 2: choose the USB. Only external removable disks appear (the internal
/// one is unreachable by design). The list updates live.
struct DiskListView: View {
    @ObservedObject var coordinator: BuildCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            VStack(alignment: .leading, spacing: Carbon.Space.xs) {
                Text("disk.title").carbon(.displayMd)
                Text("disk.subtitle")
                    .carbon(.body).foregroundStyle(Carbon.inkMuted)
            }

            if coordinator.diskService.disks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Carbon.Space.sm) {
                        ForEach(coordinator.diskService.disks) { disk in
                            DiskRow(disk: disk,
                                    verdict: disk.sizeVerdict(imageBytes: coordinator.isoInfo?.sizeBytes ?? 0,
                                                              isRawFlow: coordinator.isRawFlow),
                                    isRawFlow: coordinator.isRawFlow,
                                    selected: coordinator.selectedDisk?.id == disk.id) {
                                coordinator.selectedDisk = disk
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("common.back") { coordinator.step = .selectISO }
                    .buttonStyle(CarbonButton(kind: .ghost))
                Spacer()
                Button("common.continue") { coordinator.goToConfirm() }
                    .buttonStyle(CarbonButton(kind: .primary))
                    .disabled(coordinator.selectedDisk == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Carbon.Space.md) {
            ZStack {
                Circle().fill(Carbon.surface1).frame(width: 76, height: 76)
                Image(systemName: "externaldrive.badge.questionmark")
                    .font(.system(size: 32, weight: .regular)).foregroundStyle(Carbon.inkSubtle)
            }
            Text("disk.empty").carbon(.bodyLg).foregroundStyle(Carbon.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiskRow: View {
    let disk: Disk
    let verdict: Disk.SizeVerdict
    let isRawFlow: Bool
    let selected: Bool
    let onTap: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Carbon.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Carbon.Radius.chip, style: .continuous)
                        .fill(selected ? Carbon.primary.opacity(0.15) : Carbon.surface2)
                        .frame(width: 40, height: 40)
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? Carbon.primary : Carbon.inkMuted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(disk.displayName).carbon(.cardTitle).foregroundStyle(Carbon.ink)
                    Text(verbatim: "\(disk.devicePath) · \(disk.sizeDescription)\(disk.busProtocol.map { " · \($0)" } ?? "")")
                        .carbon(.caption).monospacedDigit().foregroundStyle(Carbon.inkMuted)
                    sizeWarning
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Carbon.primary : Carbon.hairlineStrong)
            }
            .padding(.vertical, Carbon.Space.sm + 2)
            .padding(.horizontal, Carbon.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Carbon.Radius.card, style: .continuous)
                    .stroke(borderColor, lineWidth: selected || focused ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .pointingCursor()
        .onHover { hovering = $0 }
        .animation(Carbon.Motion.fast, value: hovering)
        .animation(Carbon.Motion.fast, value: selected)
    }

    private var rowBackground: Color {
        if selected { return Carbon.primary.opacity(scheme == .dark ? 0.16 : 0.07) }
        if hovering { return Carbon.surface2 }
        return Carbon.surface1
    }

    private var borderColor: Color {
        if selected || focused { return Carbon.primary }
        return Carbon.hairline
    }

    // The size criterion depends on the flow: Windows uses fixed 8/16 GB thresholds;
    // the raw (Linux) flow only cares that the USB fits the ISO (B4).
    @ViewBuilder private var sizeWarning: some View {
        switch verdict {
        case .tooSmall:
            Label(isRawFlow ? "disk.tooSmallForISO" : "disk.tooSmall",
                  systemImage: "exclamationmark.triangle.fill")
                .carbon(.caption).foregroundStyle(Carbon.error)
        case .recommend:
            Label("disk.recommendSize", systemImage: "exclamationmark.triangle")
                .carbon(.caption).foregroundStyle(Carbon.warning)
        case .ok:
            EmptyView()
        }
    }
}
