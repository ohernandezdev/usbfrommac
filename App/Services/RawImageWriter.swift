import Foundation

/// POC de la escritura "cruda" (raw / `dd`) de un ISO isohíbrido al disco.
///
/// Mecánica: lee el ISO por bloques y los escribe secuencialmente al destino,
/// reportando bytes para progreso real y permitiendo cancelar limpio (S-5).
/// Es el MISMO patrón que `CopyService` pero a un único destino contiguo.
///
/// ⚠️ AISLADO A PROPÓSITO (POC): aún NO se invoca desde el wizard. En producción
/// `destination` sería `/dev/rdiskN` abierto por el **helper root** (la app de
/// usuario no puede escribir un block device), tras `diskutil unmountDisk`. Aquí
/// el destino es una URL cualquiera (en tests, un archivo temporal) para validar
/// la mecánica y el progreso sin riesgo. NO hay fallback: si algo falla, lanza.
public final class RawImageWriter {

    public struct Progress: Equatable {
        public let bytesWritten: UInt64
        public let totalBytes: UInt64
        public var fraction: Double {
            totalBytes == 0 ? 0 : min(1, Double(bytesWritten) / Double(totalBytes))
        }
    }

    public enum RawWriteError: LocalizedError, Equatable {
        case openSourceFailed(String)
        case openDestinationFailed(String)
        case readFailed(String)
        case writeFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .openSourceFailed(let m):      return "No se pudo abrir la imagen: \(m)"
            case .openDestinationFailed(let m):  return "No se pudo abrir el destino: \(m)"
            case .readFailed(let m):             return "Error de lectura: \(m)"
            case .writeFailed(let m):            return "Error de escritura: \(m)"
            case .cancelled:                     return "Escritura cancelada."
            }
        }
    }

    /// Bloque de 4 MiB: equilibra rendimiento y granularidad de progreso/cancelación.
    private let blockSize: Int

    public init(blockSize: Int = 4 * 1024 * 1024) {
        self.blockSize = blockSize
    }

    /// Escribe `imageURL` byte a byte en `destinationURL`. En producción el destino
    /// es un device crudo; aquí se exige que ya exista el contenedor (el helper crea
    /// el fd del device; en tests se crea el archivo).
    public func write(imageURL: URL,
                      to destinationURL: URL,
                      progress: (Progress) -> Void = { _ in },
                      isCancelled: () -> Bool = { false }) throws {

        guard let input = try? FileHandle(forReadingFrom: imageURL) else {
            throw RawWriteError.openSourceFailed(imageURL.lastPathComponent)
        }
        defer { try? input.close() }

        // El destino debe existir para abrir un handle de escritura (en producción
        // el device ya existe; en tests creamos el archivo vacío).
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        }
        guard let output = try? FileHandle(forWritingTo: destinationURL) else {
            throw RawWriteError.openDestinationFailed(destinationURL.lastPathComponent)
        }
        defer { try? output.close() }

        let total = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? NSNumber)??.uint64Value ?? 0
        var written: UInt64 = 0

        while true {
            if isCancelled() { throw RawWriteError.cancelled }
            let chunk: Data
            do {
                chunk = try input.read(upToCount: blockSize) ?? Data()
            } catch {
                throw RawWriteError.readFailed(error.localizedDescription)
            }
            if chunk.isEmpty { break }
            do {
                try output.write(contentsOf: chunk)
            } catch {
                throw RawWriteError.writeFailed(error.localizedDescription)
            }
            written += UInt64(chunk.count)
            progress(Progress(bytesWritten: written, totalBytes: total))
        }

        // Garantiza que todo llegó al medio (crítico para un device antes de expulsar).
        do { try output.synchronize() }
        catch { throw RawWriteError.writeFailed(error.localizedDescription) }
    }
}
