import Foundation
import Combine

/// Servicio observable que la UI consume: publica la lista de USB elegibles y la
/// mantiene al día en vivo (RF-1). Compone una fuente (`DiskEnumerating`) con el
/// `DiskFilter`. Toda la lógica de exclusión vive en el filtro, ya cubierto por
/// tests; este servicio solo orquesta.
///
/// Contrato de hilo: la fuente garantiza entregar `onChange` en el hilo principal,
/// por lo que `disks` se muta siempre en main (seguro para SwiftUI). Por eso el
/// tipo NO es `@MainActor`: evita fricción de aislamiento con el callback síncrono.
public final class DiskService: ObservableObject {

    /// USB elegibles, listos para mostrar. Nunca contiene el disco interno/arranque.
    @Published public private(set) var disks: [Disk] = []

    private let source: DiskEnumerating
    private let filter: DiskFilter

    /// - Parameters:
    ///   - source: por defecto DiskArbitration; en tests se inyecta un fake.
    ///   - bootDiskBSDName: disco de arranque a excluir; por defecto el real del sistema.
    public init(source: DiskEnumerating = DiskArbitrationSource(),
                bootDiskBSDName: String? = SystemBootDisk.bsdName()) {
        self.source = source
        self.filter = DiskFilter(bootDiskBSDName: bootDiskBSDName)
    }

    /// Empieza a observar discos. La fuente entrega el estado actual de inmediato.
    public func start() {
        source.onChange = { [weak self] candidates in
            // `onChange` ya llega en el hilo principal (garantía de la fuente).
            self?.apply(candidates)
        }
        source.start()
    }

    public func stop() {
        source.stop()
        source.onChange = nil
    }

    /// Snapshot síncrono filtrado (útil para revalidar antes de acciones).
    public func refreshNow() {
        apply(source.currentCandidates())
    }

    /// Snapshot filtrado SIN publicar (seguro desde un hilo de fondo). Se usa para
    /// la re-validación JIT del disco justo antes de formatear (S-3).
    public func snapshot() -> [Disk] {
        filter.eligibleDisks(from: source.currentCandidates())
    }

    private func apply(_ candidates: [DiskCandidate]) {
        disks = filter.eligibleDisks(from: candidates)
    }
}
