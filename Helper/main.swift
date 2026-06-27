import Foundation

/// Punto de entrada del privileged helper (daemon root).
///
/// Levanta un `NSXPCListener` sobre el Mach service declarado en el plist launchd
/// y atiende SOLO las llamadas del contrato `HelperProtocol`.
///
/// Fase 2 completará la validación de la firma del cliente (que el conectado sea
/// la app firmada por el mismo Team ID) antes de aceptar la conexión.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let service = HelperService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // SEGURIDAD: solo acepta conexiones de NUESTRA app firmada por NUESTRO Team ID.
        // La validación efectiva la hace el kernel/XPC cuando llega la primera llamada;
        // si el peer no cumple el requisito, la conexión se invalida automáticamente.
        newConnection.setCodeSigningRequirement(HelperConstants.clientCodeSigningRequirement)
        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

// El daemon vive hasta que launchd lo detiene.
RunLoop.main.run()
