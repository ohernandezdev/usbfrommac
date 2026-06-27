import Foundation

/// Fuente de discos: abstrae de DÓNDE vienen los candidatos crudos.
///
/// La implementación de producción (`DiskArbitrationSource`) usa DiskArbitration
/// + IOKit. En tests se usa una fuente fake que emite candidatos a voluntad, de
/// modo que `DiskService` y el filtrado se prueban sin hardware real.
public protocol DiskEnumerating: AnyObject {

    /// Se invoca con la lista COMPLETA de candidatos crudos cada vez que cambia
    /// el conjunto de discos (al conectar/desconectar). Siempre en el hilo principal.
    var onChange: (([DiskCandidate]) -> Void)? { get set }

    /// Empieza a observar y entrega de inmediato el estado actual vía `onChange`.
    func start()

    /// Deja de observar.
    func stop()

    /// Snapshot síncrono del estado actual.
    func currentCandidates() -> [DiskCandidate]
}
