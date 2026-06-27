import Foundation

/// Contrato XPC entre la app y el privileged helper (daemon root).
///
/// El helper expone EXCLUSIVAMENTE el formateo destructivo (`diskutil eraseDisk`),
/// que es la única operación que necesita root. Todo lo demás (montar el ISO,
/// copiar, dividir el .wim) corre como usuario sobre el volumen ya montado.
///
/// El protocolo se compila en ambos targets (app y helper) compartiendo este
/// archivo, que es el patrón estándar para NSXPC.
@objc public protocol HelperProtocol {

    /// Formatea `bsdName` como FAT32 con esquema GPT y la etiqueta dada.
    ///
    /// SEGURIDAD (S-4): el helper REVALIDA por su cuenta que el target sea un
    /// disco físico completo, externo y removible antes de ejecutar nada. Nunca
    /// confía ciegamente en los argumentos recibidos por XPC.
    ///
    /// - Parameters:
    ///   - bsdName: identificador BSD del disco completo, p. ej. "disk4".
    ///   - label: etiqueta FAT32 (≤ 11 caracteres, mayúsculas).
    ///   - reply: `(ok, mensajeDeError?)`.
    func eraseDisk(bsdName: String,
                   label: String,
                   reply: @escaping (Bool, String?) -> Void)

    /// Versión del helper instalado (para comprobar que app y helper concuerdan).
    /// Escribe `isoPath` CRUDO (raw, estilo `dd`) sobre el disco `bsdName`.
    ///
    /// Para ISOs isohíbridos (Linux/BSD) que deben volcarse byte a byte al device.
    /// Aplica las MISMAS salvaguardas que `eraseDisk` (S-4): revalida que el target
    /// sea whole + externo + extraíble y que NO sea el disco de arranque, desmonta
    /// el disco y escribe sobre `/dev/rdiskN`. El progreso se reporta por el canal
    /// inverso (`HelperProgressProtocol`).
    ///
    /// - Parameters:
    ///   - isoPath: ruta absoluta del archivo .iso a volcar.
    ///   - bsdName: identificador BSD del disco completo, p. ej. "disk4".
    ///   - reply: `(ok, mensajeDeError?)`.
    func writeImage(isoPath: String,
                    bsdName: String,
                    reply: @escaping (Bool, String?) -> Void)

    /// Versión del helper instalado (para comprobar que app y helper concuerdan).
    func helperVersion(reply: @escaping (String) -> Void)
}

/// Canal inverso de progreso: lo implementa la APP y lo invoca el HELPER durante
/// una operación larga (escritura raw) para reportar bytes escritos en vivo.
@objc public protocol HelperProgressProtocol {
    func didWrite(bytes: Int64, of total: Int64)
}

/// Constantes compartidas app ↔ helper.
public enum HelperConstants {
    /// Nombre del Mach service (debe coincidir con el plist launchd y SMAppService).
    public static let machServiceName = "com.omar.winusbmac.helper"

    /// Nombre del plist launchd embebido (lo usa SMAppService.daemon(plistName:)).
    public static let plistName = "com.omar.winusbmac.helper.plist"

    /// Versión del contrato/helper.
    public static let version = "1.0.0"

    /// Longitud máxima de una etiqueta FAT32.
    public static let maxFAT32LabelLength = 11

    public static let appBundleID = "com.omar.winusbmac"
    public static let helperBundleID = "com.omar.winusbmac.helper"

    // Apple Team ID: OU del certificado Developer ID; valida la firma cruzada XPC.
    // (Team de Omar — Developer ID Application C34D3V8484.) Con firma ad-hoc local
    // ("-") esta validación NO se cumple (es esperado): solo aplica a builds
    // firmados con Developer ID / Apple Development de este mismo equipo.
    public static let teamID = "C34D3V8484"

    /// Requisito que la APP exige al HELPER (que el helper sea tuyo y no esté suplantado).
    public static var helperCodeSigningRequirement: String {
        "identifier \"\(helperBundleID)\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Requisito que el HELPER exige al CLIENTE (que quien le pide formatear sea tu app).
    public static var clientCodeSigningRequirement: String {
        "identifier \"\(appBundleID)\" and anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
