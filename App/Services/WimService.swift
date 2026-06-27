import Foundation

public enum WimConstants {
    /// Tamaño objetivo de cada fragmento, en MiB. Es un OBJETIVO, no un tope:
    /// un recurso no se parte entre fragmentos, por eso 3800 (no 4096) para dejar
    /// margen bajo el techo de 4 GiB de FAT32 (verificado: wimlib LIMITATIONS).
    public static let partSizeMiB = 3800

    /// El primer fragmento DEBE llamarse install.swm; wimlib genera install2.swm,
    /// install3.swm… automáticamente. Windows Setup los reensambla solo en sources/.
    public static let firstSWMName = "install.swm"

    /// Nombre del binario empaquetado.
    public static let binaryName = "wimlib-imagex"
}

/// Abstracción del divisor de WIM: permite cambiar la implementación (binario
/// como subproceso ↔ libwim enlazado) sin tocar el resto de la app.
public protocol WimSplitting {
    func split(wim: URL,
               intoSourcesDir: URL,
               partSizeMiB: Int,
               progress: (Double) -> Void,
               isCancelled: () -> Bool) throws
}

/// Divide `sources/install.wim` en `.swm` con `wimlib-imagex` (RF-8).
///
/// El binario se ejecuta como subproceso (la app es open source / GPLv3, así que
/// no hay conflicto de licencia). NO hay fallback a un wimlib del sistema: si el
/// binario no está empaquetado, falla con un error claro (config manual de Fase 8).
public final class WimService: WimSplitting {

    public enum WimError: LocalizedError, Equatable {
        case binaryNotBundled
        case splitFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .binaryNotBundled:
                return loc("error.wim.binaryNotBundled")
            case .splitFailed(let m):
                return loc("error.wim.splitFailed \(m)")
            case .cancelled:
                return loc("error.wim.cancelled")
            }
        }
    }

    private let binaryURL: URL?

    /// Por defecto usa el binario empaquetado. En desarrollo/tests se puede inyectar
    /// una ruta explícita (p. ej. el de Homebrew). Esto es configuración explícita,
    /// no un fallback silencioso.
    public init(binaryURL: URL? = WimService.bundledBinaryURL()) {
        self.binaryURL = binaryURL
    }

    public static func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: WimConstants.binaryName, withExtension: nil)
    }

    public func split(wim: URL,
                      intoSourcesDir: URL,
                      partSizeMiB: Int = WimConstants.partSizeMiB,
                      progress: (Double) -> Void = { _ in },
                      isCancelled: () -> Bool = { false }) throws {

        guard let binary = binaryURL else { throw WimError.binaryNotBundled }

        let firstSWM = intoSourcesDir.appendingPathComponent(WimConstants.firstSWMName)
        let (launch, args) = Self.splitCommand(binary: binary, wim: wim,
                                               firstSWM: firstSWM, partSizeMiB: partSizeMiB)

        let wimSize = (try? FileManager.default.attributesOfItem(atPath: wim.path)[.size] as? NSNumber)??.uint64Value ?? 0

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw WimError.splitFailed(error.localizedDescription)
        }

        // Progreso robusto: medir lo escrito en los .swm vs el tamaño del wim.
        // No depende del formato de salida de wimlib (que puede cambiar).
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                try? Self.cleanupSWM(in: intoSourcesDir)
                throw WimError.cancelled
            }
            if wimSize > 0 {
                let written = Self.writtenSWMBytes(in: intoSourcesDir)
                progress(min(0.99, Double(written) / Double(wimSize)))
            }
            usleep(200_000) // 200 ms
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? Self.cleanupSWM(in: intoSourcesDir)
            throw WimError.splitFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        progress(1.0)
    }

    // MARK: - Lógica pura (testeable sin binario)

    /// Construye el comando: `wimlib-imagex split <wim> <install.swm> <partSize>`.
    public static func splitCommand(binary: URL, wim: URL, firstSWM: URL, partSizeMiB: Int) -> (launch: String, args: [String]) {
        (binary.path, ["split", wim.path, firstSWM.path, String(partSizeMiB)])
    }

    /// Nombre del fragmento n.º `index` (1 → install.swm, 2 → install2.swm…).
    public static func expectedSWMName(index: Int) -> String {
        index <= 1 ? "install.swm" : "install\(index).swm"
    }

    /// Estimación (cota inferior) del número de fragmentos: ceil(tamaño / parte).
    /// El real puede ser igual o uno más (un recurso no se parte entre fragmentos).
    public static func minimumPartCount(wimSizeBytes: UInt64, partSizeMiB: Int) -> Int {
        guard wimSizeBytes > 0, partSizeMiB > 0 else { return 0 }
        let partBytes = UInt64(partSizeMiB) * 1024 * 1024
        return Int((wimSizeBytes + partBytes - 1) / partBytes)
    }

    // MARK: - Privado

    private static func writtenSWMBytes(in dir: URL) -> UInt64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items
            .filter { isSWM($0) }
            .reduce(0) { acc, url in
                acc + UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
    }

    private static func cleanupSWM(in dir: URL) throws {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items where isSWM(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func isSWM(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased().hasPrefix("install")
            && url.pathExtension.lowercased() == "swm"
    }
}
