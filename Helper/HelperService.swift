import Foundation

/// Implementación del contrato XPC en el lado root.
///
/// Es deliberadamente AUTOCONTENIDO (no comparte código con la app salvo el
/// protocolo): minimiza la superficie de ataque del componente privilegiado y
/// garantiza que la revalidación de seguridad no depende de la lógica de la app.
final class HelperService: NSObject, HelperProtocol {

    private let diskutil = "/usr/sbin/diskutil"

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func eraseDisk(bsdName: String,
                   label: String,
                   reply: @escaping (Bool, String?) -> Void) {

        // 1. El identificador debe ser un disco COMPLETO: "diskN", sin sufijos de
        //    partición ni rutas. Bloquea inyección y formateo de particiones sueltas.
        guard Self.isValidWholeDiskBSD(bsdName) else {
            return reply(false, "Identificador de disco no válido: \(bsdName)")
        }

        // 2. Etiqueta FAT32 saneada (≤ 11, charset seguro).
        guard let safeLabel = Self.sanitizedFAT32Label(label) else {
            return reply(false, "Etiqueta FAT32 no válida (máx. 11 caracteres permitidos).")
        }

        // 3. No puede ser el disco de arranque (revalidado aquí, no se confía en la app).
        if let boot = Self.bootDiskBSDName(), boot == bsdName {
            return reply(false, "Operación rechazada: el target es el disco de arranque del sistema.")
        }

        // 4. REVALIDACIÓN INDEPENDIENTE (S-4): el helper consulta diskutil y exige
        //    que el target sea whole + NO interno + extraíble. Si algo no encaja,
        //    aborta sin tocar nada.
        if case .failure(let message) = Self.validateRemovableExternal(bsdName, diskutil: diskutil) {
            return reply(false, message)
        }

        // 5. Solo aquí, con todo validado, se formatea.
        let result = Self.runDiskutilErase(bsdName: bsdName, label: safeLabel, diskutil: diskutil)
        reply(result.ok, result.message)
    }

    // MARK: - Validación

    static func isValidWholeDiskBSD(_ bsd: String) -> Bool {
        bsd.range(of: "^disk[0-9]+$", options: .regularExpression) != nil
    }

    static func sanitizedFAT32Label(_ label: String) -> String? {
        let upper = label.uppercased()
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard !upper.isEmpty,
              upper.count <= HelperConstants.maxFAT32LabelLength,
              upper.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return upper
    }

    enum ValidationResult { case success, failure(String) }

    static func validateRemovableExternal(_ bsd: String, diskutil: String) -> ValidationResult {
        let r = runProcess(diskutil, ["info", "-plist", "/dev/\(bsd)"])
        guard r.status == 0,
              let plist = (try? PropertyListSerialization.propertyList(from: r.stdout,
                                                                       options: [],
                                                                       format: nil)) as? [String: Any] else {
            return .failure("No se pudo leer la información del disco \(bsd).")
        }
        let whole = (plist["WholeDisk"] as? Bool) ?? false
        // Fail-safe: si no se conoce, se trata como interno (rechazar).
        let isInternal = (plist["Internal"] as? Bool) ?? true
        let ejectable = (plist["Ejectable"] as? Bool) ?? false
        let removable = (plist["RemovableMedia"] as? Bool) ?? false

        guard whole else { return .failure("El target no es un disco físico completo.") }
        guard !isInternal else { return .failure("El target es un disco interno. Operación rechazada.") }
        guard ejectable || removable else {
            return .failure("El target no es un medio extraíble. Operación rechazada.")
        }
        return .success
    }

    // MARK: - Formateo

    static func runDiskutilErase(bsdName: String, label: String, diskutil: String) -> (ok: Bool, message: String?) {
        let r = runProcess(diskutil, ["eraseDisk", "MS-DOS", label, "GPT", "/dev/\(bsdName)"])
        if r.status == 0 { return (true, nil) }
        let err = String(data: r.stderr, encoding: .utf8) ?? ""
        let out = String(data: r.stdout, encoding: .utf8) ?? ""
        let message = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, message.isEmpty ? "diskutil falló (código \(r.status))." : message)
    }

    // MARK: - Utilidades

    /// Disco físico que respalda "/", normalizado a "diskN".
    static func bootDiskBSDName() -> String? {
        var s = statfs()
        guard statfs("/", &s) == 0 else { return nil }
        let from = withUnsafeBytes(of: &s.f_mntfromname) { raw -> String in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let dev = from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
        guard dev.hasPrefix("disk") else { return nil }
        let digits = dev.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? nil : "disk" + digits
    }

    static func runProcess(_ launchPath: String, _ args: [String]) -> (status: Int32, stdout: Data, stderr: Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return (-1, Data(), Data("No se pudo ejecutar \(launchPath): \(error)".utf8))
        }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, oData, eData)
    }
}
