import SwiftUI

/// Host del wizard de 4 pasos, con chrome Carbon (canvas, charcoal, plano) y
/// soporte de claro/oscuro, transiciones direccionales y barra de pasos navegable.
struct ContentView: View {
    @StateObject private var coordinator = BuildCoordinator()
    @ObservedObject private var localization = LocalizationStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastIndex = 0
    @State private var direction: Edge = .trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Carbon.Space.md) {
                CarbonStepBar(step: coordinator.step,
                              isBuilding: coordinator.isBuilding,
                              onSelect: navigate)
                LanguageMenu(localization: localization)
            }
            .padding(.horizontal, Carbon.Space.xl)
            .padding(.top, Carbon.Space.lg)
            .padding(.bottom, Carbon.Space.md)

            Group {
                switch coordinator.step {
                case .selectISO:  ISOPickerView(coordinator: coordinator)
                case .selectDisk: DiskListView(coordinator: coordinator)
                case .confirm:    ConfirmView(coordinator: coordinator)
                case .build:      BuildProgressView(coordinator: coordinator)
                }
            }
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, Carbon.Space.xl)
            .padding(.bottom, Carbon.Space.lg)
            .id(coordinator.step)
            .transition(.asymmetric(
                insertion: .move(edge: direction).combined(with: .opacity),
                removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)))
        }
        .background(Carbon.canvas)
        .foregroundStyle(Carbon.ink)
        .tint(Carbon.primary)
        .environment(\.locale, localization.locale)
        .id(localization.language)   // fuerza el re-render de toda la UI al cambiar idioma
        .animation(Carbon.Motion.resolve(Carbon.Motion.standard, reduce: reduceMotion),
                   value: coordinator.step)
        .onChange(of: coordinator.step) { _ in updateDirection() }
    }

    /// Navega a un paso ya visitado al tocar la barra de pasos.
    private func navigate(to step: BuildCoordinator.Step) {
        coordinator.goTo(step: step)
    }

    /// Determina la dirección de la transición (avanzar = entra por la derecha).
    private func updateDirection() {
        let newIndex = stepIndex(coordinator.step)
        direction = newIndex >= lastIndex ? .trailing : .leading
        lastIndex = newIndex
    }

    private func stepIndex(_ s: BuildCoordinator.Step) -> Int {
        switch s { case .selectISO: return 0; case .selectDisk: return 1; case .confirm: return 2; case .build: return 3 }
    }
}

/// Indicador de pasos Carbon: cuadrados (0px) unidos por hairlines. Los pasos ya
/// visitados son clicables para volver (si no hay un build en curso).
private struct CarbonStepBar: View {
    let step: BuildCoordinator.Step
    let isBuilding: Bool
    let onSelect: (BuildCoordinator.Step) -> Void

    private let items: [(BuildCoordinator.Step, LocalizedStringKey)] = [
        (.selectISO, "step.iso"),
        (.selectDisk, "step.usb"),
        (.confirm, "step.confirm"),
        (.build, "step.create")
    ]

    private func idx(_ s: BuildCoordinator.Step) -> Int {
        switch s { case .selectISO: return 0; case .selectDisk: return 1; case .confirm: return 2; case .build: return 3 }
    }

    var body: some View {
        HStack(spacing: Carbon.Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let current = idx(step) == i
                let past = i < idx(step)
                let reachable = past && !isBuilding

                stepChip(index: i, title: item.1, current: current, past: past)
                    .contentShape(Rectangle())
                    .onTapGesture { if reachable { onSelect(item.0) } }
                    .pointingCursor()
                    .help(reachable ? Text("step.goBack") : Text(""))

                if i < items.count - 1 {
                    Capsule()
                        .fill(i < idx(step) ? Carbon.primary : Carbon.hairlineStrong)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Carbon.Space.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Carbon.Motion.standard, value: idx(step))
    }

    private func stepChip(index i: Int, title: LocalizedStringKey, current: Bool, past: Bool) -> some View {
        HStack(spacing: Carbon.Space.xs) {
            ZStack {
                Circle()
                    .fill(current ? AnyShapeStyle(Carbon.primaryGradient)
                                  : (past ? AnyShapeStyle(Carbon.primary) : AnyShapeStyle(Carbon.surface2)))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Carbon.hairline, lineWidth: past || current ? 0 : 1))
                if past {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Carbon.onPrimary)
                } else {
                    Text(verbatim: "\(i + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(current ? Carbon.onPrimary : Carbon.inkSubtle)
                }
            }
            Text(title).carbon(.bodySm)
                .fontWeight(current ? .semibold : .regular)
                .foregroundStyle(current ? Carbon.ink : Carbon.inkMuted)
                .fixedSize()
        }
    }
}

/// Selector de idioma de la interfaz (Sistema / English / Español), en vivo.
private struct LanguageMenu: View {
    @ObservedObject var localization: LocalizationStore

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    localization.language = lang
                } label: {
                    if localization.language == lang {
                        Label(lang.displayName, systemImage: "checkmark")
                    } else {
                        Text(lang.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: Carbon.Space.xxs) {
                Image(systemName: "globe")
                Text(localization.language.displayName).carbon(.bodySm)
            }
            .foregroundStyle(Carbon.inkMuted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointingCursor()
        .help(Text("lang.menu.help"))
    }
}

#Preview {
    ContentView().frame(width: 660, height: 580)
}
