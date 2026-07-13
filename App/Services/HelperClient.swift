import Foundation
import ServiceManagement

/// Lifecycle errors for the privileged helper.
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

/// Client for the privileged helper: registers it with SMAppService and talks to it
/// over XPC for the ONLY root operation (formatting). Validates by signature that the
/// helper it connects to is the legitimate one (anti-spoofing).
public final class HelperClient {

    public init() {}

    // MARK: - Registration (SMAppService)

    public var status: SMAppService.Status {
        SMAppService.daemon(plistName: HelperConstants.plistName).status
    }

    /// Registers the daemon if it isn't already. Idempotent.
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
                // Registering a root daemon almost always requires user approval;
                // macOS returns "Operation not permitted" until it's approved in
                // Settings. We show the friendly guidance, not the raw error.
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

    /// Runs an XPC call with ALL resolution paths covered (reply, send error,
    /// interruption, invalidation) → the continuation resumes EXACTLY once and the
    /// call never hangs at the XPC level.
    /// Uses a dedicated connection per call (the root operation is one-shot).
    private func withProxy<T>(_ body: @escaping (HelperProtocol, ResumeOnce, CheckedContinuation<T, Error>) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = ResumeOnce()
            let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                       options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            // Anti-spoofing: we only talk to the helper signed with our Team ID.
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

    /// Formats the disk (root operation). Throws if the helper rejects or fails.
    public func eraseDisk(bsdName: String, label: String) async throws {
        try await withProxy { (proxy, once, cont: CheckedContinuation<Void, Error>) in
            proxy.eraseDisk(bsdName: bsdName, label: label) { ok, message in
                once.resume {
                    if ok { cont.resume() }
                    else { cont.resume(throwing: HelperClientError.remote(message ?? "Unknown error while formatting.")) }
                }
            }
        }
    }

    /// Version of the installed helper (sanity check that app and helper match).
    public func helperVersion() async throws -> String {
        try await withProxy { (proxy, once, cont: CheckedContinuation<String, Error>) in
            proxy.helperVersion { version in
                once.resume { cont.resume(returning: version) }
            }
        }
    }

    /// Writes a RAW isohybrid ISO to the disk (long root operation).
    /// Reports progress over the reverse channel (`onProgress`, on a background thread).
    /// Uses a dedicated connection that exports the progress receiver.
    public func writeImage(isoPath: String, bsdName: String,
                           onProgress: @escaping (Int64, Int64) -> Void) async throws {
        let receiver = ProgressReceiver(onProgress)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            conn.setCodeSigningRequirement(HelperConstants.helperCodeSigningRequirement)
            // Export the progress receiver so the helper can call us back.
            conn.exportedInterface = NSXPCInterface(with: HelperProgressProtocol.self)
            conn.exportedObject = receiver
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
            proxy.writeImage(isoPath: isoPath, bsdName: bsdName) { ok, message in
                once.resume {
                    if ok { cont.resume() }
                    else { cont.resume(throwing: HelperClientError.remote(message ?? "Unknown error while writing the image.")) }
                }
            }
        }
    }
}

/// Receiver for the helper's reverse progress channel (root → app).
private final class ProgressReceiver: NSObject, HelperProgressProtocol {
    private let onProgress: (Int64, Int64) -> Void
    init(_ onProgress: @escaping (Int64, Int64) -> Void) { self.onProgress = onProgress }
    func didWrite(bytes: Int64, of total: Int64) { onProgress(bytes, total) }
}

/// Guarantees that an XPC continuation resumes EXACTLY once, even if the reply, the
/// error, and the connection handlers end up racing (resuming twice is a crash).
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
