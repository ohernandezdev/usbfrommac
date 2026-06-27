import Foundation
import ServiceManagement

/// Errores del ciclo de vida del helper privilegiado.
public enum HelperClientError: LocalizedError {
    case registrationFailed(String)
    case requiresApproval
    case connectionFailed
    case interrupted
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let m):
            return loc("error.helper.registrationFailed \(m)")
        case .requiresApproval:
            return loc("error.helper.requiresApproval")
        case .connectionFailed:
            return loc("error.helper.connectionFailed")
        case .interrupted:
            return loc("error.helper.interrupted")
        case .remote(let m):
            return m
        }
    }
}

/// Cliente del privileged helper: lo registra con SMAppService y habla con él por
/// XPC para la ÚNICA operación root (formatear). Valida por firma que el helper al
/// que se conecta es el legítimo (anti-suplantación).
public final class HelperClient {

    public init() {}

    // MARK: - Registro (SMAppService)

    public var status: SMAppService.Status {
        SMAppService.daemon(plistName: HelperConstants.plistName).status
    }

    /// Registra el daemon si aún no lo está. Idempotente.
    public func registerIfNeeded() throws {
        let service = SMAppService.daemon(plistName: HelperConstants.plistName)
        switch service.status {
        case .enabled:
            return
        case .requiresApproval:
            throw HelperClientError.requiresApproval
        default:
            do {
                try service.register()
            } catch {
                // Registrar un daemon root casi siempre exige aprobación del usuario;
                // macOS devuelve "Operation not permitted" hasta que se aprueba en
                // Ajustes. Mostramos la guía amable, no el error crudo.
                if service.status == .requiresApproval {
                    throw HelperClientError.requiresApproval
                }
                throw HelperClientError.registrationFailed(error.localizedDescription)
            }
            if service.status == .requiresApproval {
                throw HelperClientError.requiresApproval
            }
        }
    }

    public func unregister() throws {
        try SMAppService.daemon(plistName: HelperConstants.plistName).unregister()
    }

    // MARK: - XPC

    /// Ejecuta una llamada XPC con TODOS los caminos de resolución cubiertos
    /// (reply, error de envío, interrupción, invalidación) → la continuación se
    /// reanuda EXACTAMENTE una vez y la llamada nunca se cuelga a nivel XPC.
    /// Usa una conexión dedicada por llamada (la operación root es de una sola vez).
    private func withProxy<T>(_ body: @escaping (HelperProtocol, ResumeOnce, CheckedContinuation<T, Error>) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = ResumeOnce()
            let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                       options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            // Anti-suplantación: solo hablamos con el helper firmado por nuestro Team ID.
            conn.setCodeSigningRequirement(HelperConstants.helperCodeSigningRequirement)
            conn.invalidationHandler = { once.resume { cont.resume(throwing: HelperClientError.connectionFailed) } }
            conn.interruptionHandler = { once.resume { cont.resume(throwing: HelperClientError.interrupted) } }
            conn.resume()

            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
                once.resume { cont.resume(throwing: HelperClientError.remote(error.localizedDescription)) }
            }) as? HelperProtocol else {
                once.resume { cont.resume(throwing: HelperClientError.connectionFailed) }
                conn.invalidate()
                return
            }
            body(proxy, once, cont)
        }
    }

    /// Formatea el disco (operación root). Lanza si el helper rechaza o falla.
    public func eraseDisk(bsdName: String, label: String) async throws {
        try await withProxy { (proxy, once, cont: CheckedContinuation<Void, Error>) in
            proxy.eraseDisk(bsdName: bsdName, label: label) { ok, message in
                once.resume {
                    if ok { cont.resume() }
                    else { cont.resume(throwing: HelperClientError.remote(message ?? "Error desconocido al formatear.")) }
                }
            }
        }
    }

    /// Versión del helper instalado (sanity check de que app y helper concuerdan).
    public func helperVersion() async throws -> String {
        try await withProxy { (proxy, once, cont: CheckedContinuation<String, Error>) in
            proxy.helperVersion { version in
                once.resume { cont.resume(returning: version) }
            }
        }
    }
}

/// Garantiza que una continuación XPC se reanuda EXACTAMENTE una vez, aunque el
/// reply, el error y los handlers de conexión lleguen a competir (reanudar dos
/// veces es un crash).
private final class ResumeOnce {
    private let lock = NSLock()
    private var done = false
    func resume(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        block()
    }
}
