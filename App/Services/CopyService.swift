import Foundation

/// Progreso de copia (bytes y archivo actual).
public struct CopyProgress: Equatable {
    public let bytesCopied: UInt64
    public let totalBytes: UInt64
    public let currentFile: String

    public var fraction: Double {
        totalBytes == 0 ? 0 : min(1, Double(bytesCopied) / Double(totalBytes))
    }
}

public enum CopyServiceError: LocalizedError, Equatable {
    case cancelled
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return loc("error.copy.cancelled")
        case .readFailed(let m): return loc("error.copy.readFailed \(m)")
        case .writeFailed(let m): return loc("error.copy.writeFailed \(m)")
        }
    }
}

/// Copia el contenido del ISO montado al USB EXCLUYENDO archivos concretos
/// (RF-7: todo menos `sources/install.wim`). Copia por streaming para reportar
/// progreso por bytes y poder cancelar de forma limpia a mitad (S-5).
public final class CopyService {

    private let chunkSize = 4 * 1024 * 1024

    public init() {}

    /// - Parameters:
    ///   - sourceRoot: raíz del ISO montado.
    ///   - destinationRoot: raíz del volumen USB.
    ///   - excluding: rutas relativas a excluir (p. ej. "sources/install.wim").
    ///     La comparación es case-insensitive (los montajes UDF lo son).
    public func copy(from sourceRoot: URL,
                     to destinationRoot: URL,
                     excluding: Set<String> = ["sources/install.wim"],
                     progress: (CopyProgress) -> Void = { _ in },
                     isCancelled: () -> Bool = { false }) throws {

        let fm = FileManager.default
        let excludedLower = Set(excluding.map { $0.lowercased() })

        // 1. Enumerar archivos a copiar y calcular el total (excluye lo apartado).
        var files: [(src: URL, rel: String, size: UInt64)] = []
        var total: UInt64 = 0

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: sourceRoot,
                                             includingPropertiesForKeys: keys,
                                             options: [],
                                             errorHandler: nil) else {
            throw CopyServiceError.readFailed(sourceRoot.path)
        }

        while let item = enumerator.nextObject() as? URL {
            if isCancelled() { throw CopyServiceError.cancelled }
            let rel = Self.relativePath(of: item, base: sourceRoot)
            let values = try? item.resourceValues(forKeys: Set(keys))

            if excludedLower.contains(rel.lowercased()) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isRegularFile == true {
                let size = UInt64(values?.fileSize ?? 0)
                files.append((item, rel, size))
                total += size
            }
        }

        // 2. Copiar por streaming, creando subdirectorios según haga falta.
        var copied: UInt64 = 0
        for f in files {
            if isCancelled() { throw CopyServiceError.cancelled }
            let dest = destinationRoot.appendingPathComponent(f.rel)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
            } catch {
                throw CopyServiceError.writeFailed(error.localizedDescription)
            }
            try streamCopy(from: f.src, to: dest, isCancelled: isCancelled) { n in
                copied += n
                progress(CopyProgress(bytesCopied: copied, totalBytes: total, currentFile: f.rel))
            }
        }
    }

    // MARK: - Privado

    private func streamCopy(from src: URL,
                            to dest: URL,
                            isCancelled: () -> Bool,
                            onChunk: (UInt64) -> Void) throws {
        guard let input = try? FileHandle(forReadingFrom: src) else {
            throw CopyServiceError.readFailed(src.lastPathComponent)
        }
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: dest) else {
            try? input.close()
            throw CopyServiceError.writeFailed(dest.lastPathComponent)
        }
        defer { try? input.close(); try? output.close() }

        while true {
            if isCancelled() { throw CopyServiceError.cancelled }
            let data: Data
            do {
                data = try input.read(upToCount: chunkSize) ?? Data()
            } catch {
                throw CopyServiceError.readFailed(error.localizedDescription)
            }
            if data.isEmpty { break }
            do {
                try output.write(contentsOf: data)
            } catch {
                throw CopyServiceError.writeFailed(error.localizedDescription)
            }
            onChunk(UInt64(data.count))
        }
    }

    /// Ruta relativa de `url` respecto a `base`, sin barra inicial.
    static func relativePath(of url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(basePath) else { return url.lastPathComponent }
        return String(path.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
