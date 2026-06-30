import Foundation

/// Entry point of the privileged helper (root daemon).
///
/// Spins up an `NSXPCListener` on the Mach service declared in the launchd plist
/// and serves ONLY the calls of the `HelperProtocol` contract.
///
/// Phase 2 will complete the client signature validation (verifying that the
/// peer is the app signed by the same Team ID) before accepting the connection.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let service = HelperService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // SECURITY: only accept connections from OUR app signed by OUR Team ID.
        // The actual validation is done by the kernel/XPC when the first call arrives;
        // if the peer doesn't meet the requirement, the connection is invalidated automatically.
        newConnection.setCodeSigningRequirement(HelperConstants.clientCodeSigningRequirement)
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = service
        // Reverse channel: the helper can call the app's progress object during the
        // raw write (a long-running operation).
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProgressProtocol.self)
        newConnection.resume()
        return true
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// The daemon lives until launchd stops it.
RunLoop.main.run()
