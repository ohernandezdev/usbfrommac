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

    // MARK: - Escritura raw (ISOs isohíbridos / Linux)

    func writeImage(isoPath: String,
                    bsdName: String,
                    reply: @escaping (Bool, String?) -> Void) {

        // Mismas salvaguardas que el formateo: el raw write es igual de destructivo.
        guard Self.isValidWholeDiskBSD(bsdName) else {
            return reply(false, "Identificador de disco no válido: \(bsdName)")
        }
        guard FileManager.default.fileExists(atPath: isoPath) else {
            return reply(false, "No se encontró la imagen en \(isoPath).")
        }
        if let boot = Self.bootDiskBSDName(), boot == bsdName {
            return reply(false, "Operación rechazada: el target es el disco de arranque del sistema.")
        }
        if case .failure(let message) = Self.validateRemovableExternal(bsdName, diskutil: diskutil) {
            return reply(false, message)
        }

        // Hay que desmontar TODO el disco antes de escribir el device crudo.
        let unmount = Self.runProcess(diskutil, ["unmountDisk", "force", "/dev/\(bsdName)"])
        guard unmount.status == 0 else {
            let msg = String(data: unmount.stderr, encoding: .utf8) ?? ""
            return reply(false, "No se pudo desmontar el disco antes de escribir: \(msg)")
        }

        // Canal inverso de progreso hacia la app (si está disponible).
        let progress = NSXPCConnection.current()?.remoteObjectProxy as? HelperProgressProtocol

        let result = Self.rawWrite(isoPath: isoPath, bsdName: bsdName) { written, total in
            progress?.didWrite(bytes: written, of: total)
        }
        if result.ok {
            _ = Self.runProcess(diskutil, ["eject", "/dev/\(bsdName)"])
        }
        reply(result.ok, result.message)
    }

    /// Vuelca el ISO byte a byte sobre `/dev/rdiskN` (device crudo, rápido).
    /// Escrituras alineadas al tamaño de bloque del device (el último bloque se
    /// rellena con ceros, inocuo). Sin fallback: cualquier fallo de IO aborta.
    static func rawWrite(isoPath: String,
                         bsdName: String,
                         progress: (Int64, Int64) -> Void) -> (ok: Bool, message: String?) {

        let total = (try? FileManager.default.attributesOfItem(atPath: isoPath)[.size] as? NSNumber)??.int64Value ?? 0

        guard let input = FileHandle(forReadingAtPath: isoPath) else {
            return (false, "No se pudo abrir la imagen para lectura.")
        }
        defer { try? input.close() }

        // Device crudo: /dev/rdiskN es mucho más rápido que /dev/diskN.
        let fd = open("/dev/r\(bsdName)", O_RDWR)
        guard fd >= 0 else {
            return (false, "No se pudo abrir el device /dev/r\(bsdName) (errno \(errno)).")
        }
        defer { close(fd) }

        // Tamaño de bloque físico del device (para alinear escrituras).
        var blockSize: UInt32 = 512
        _ = ioctl(fd, 0x40046418 /* DKIOCGETBLOCKSIZE */, &blockSize)
        let bs = Int(blockSize == 0 ? 512 : blockSize)
        let chunk = max(bs, (4 * 1024 * 1024 / bs) * bs)   // ~4 MiB, múltiplo del bloque

        var writtenTotal: Int64 = 0
        while true {
            let data = (try? input.read(upToCount: chunk)) ?? Data()
            if data.isEmpty { break }

            // Alinea el último bloque: rellena con ceros hasta un múltiplo del bloque.
            var buf = data
            if buf.count % bs != 0 {
                buf.append(Data(count: bs - (buf.count % bs)))
            }

            let wrote: Int = buf.withUnsafeBytes { raw in
                write(fd, raw.baseAddress, buf.count)
            }
            if wrote < 0 {
                return (false, "Error de escritura en el device (errno \(errno)).")
            }
            writtenTotal += Int64(data.count)
            progress(min(writtenTotal, total), total)
        }

        guard fcntl(fd, F_FULLFSYNC) == 0 else {
            return (false, "No se pudo sincronizar el device (errno \(errno)).")
        }
        return (true, nil)
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
        // Defensa en profundidad (S-4): rechazar dispositivos virtuales / imágenes
        // de disco aunque se presenten como externos+removibles.
        let virtualOrPhysical = (plist["VirtualOrPhysical"] as? String) ?? ""

        guard whole else { return .failure("El target no es un disco físico completo.") }
        guard !isInternal else { return .failure("El target es un disco interno. Operación rechazada.") }
        guard virtualOrPhysical.caseInsensitiveCompare("Virtual") != .orderedSame else {
            return .failure("El target es un dispositivo virtual (imagen de disco). Operación rechazada.")
        }
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
