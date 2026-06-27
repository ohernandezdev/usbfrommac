import SwiftUI

/// Paso 3: confirmación destructiva explícita (S-2). Muestra nombre y tamaño
/// exactos y exige una acción deliberada del usuario antes de habilitar el botón.
struct ConfirmView: View {
    @ObservedObject var coordinator: BuildCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Carbon.Space.lg) {
            Text("confirm.title").carbon(.displayMd)

            if let disk = coordinator.selectedDisk {
                VStack(alignment: .leading, spacing: Carbon.Space.md) {
                    HStack(spacing: Carbon.Space.xs) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Carbon.error)
                        Text("confirm.willErase").carbon(.bodyEmphasis).foregroundStyle(Carbon.ink)
                    }
                    HStack(spacing: Carbon.Space.md) {
                        Image(systemName: "externaldrive.fill").font(.largeTitle).foregroundStyle(Carbon.error)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disk.displayName).carbon(.cardTitle).foregroundStyle(Carbon.ink)
                            Text(verbatim: "\(disk.devicePath) · \(disk.sizeDescription)")
                                .carbon(.bodySm).foregroundStyle(Carbon.inkMuted)
                        }
                    }
                }
                .carbonCard(surface: Carbon.surface1)

                labelField

                Toggle(isOn: $coordinator.confirmedDestructive) {
                    Text("confirm.acknowledge \(disk.displayName)")
                        .carbon(.bodySm)
                }
                .toggleStyle(.checkbox)
                .tint(Carbon.primary)
            }

            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("common.back") { coordinator.step = .selectDisk }
                    .buttonStyle(CarbonButton(kind: .ghost))
                Spacer()
                Button { coordinator.startBuild() } label: {
                    Label("confirm.formatAndCreate", systemImage: "bolt.fill")
                }
                .buttonStyle(CarbonButton(kind: .danger))
                .disabled(!coordinator.canStartBuild)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Carbon.Space.sm)
            .background(Carbon.canvas)
        }
    }

    private var labelField: some View {
        HStack(spacing: Carbon.Space.sm) {
            Text("confirm.usbName").carbon(.bodySm).foregroundStyle(Carbon.inkMuted)
            CarbonTextField(placeholder: "WIN11", text: Binding(
                get: { coordinator.label },
                set: { coordinator.label = FAT32Label.sanitize($0) }
            ))
            .frame(width: 160)
            Text(verbatim: "\(coordinator.label.count)/11").carbon(.caption).monospacedDigit().foregroundStyle(Carbon.inkSubtle)
        }
    }
}
