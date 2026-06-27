import Foundation

/// Ejecución de subprocesos como usuario (hdiutil, diskutil info, wimlib…).
/// El formateo root NO pasa por aquí: va por el helper XPC.
public enum Subprocess {

    public struct Result {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data

        public var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
        public var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
        public var succeeded: Bool { status == 0 }
        /// Mensaje de error preferente: stderr y, si está vacío, stdout.
        public var errorMessage: String {
            let e = stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            let o = stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? o : e
        }
    }

    /// Ejecuta y captura salida de forma síncrona.
    @discardableResult
    public static func run(_ launchPath: String, _ args: [String]) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return Result(status: -1, stdout: Data(),
                          stderr: Data("No se pudo ejecutar \(launchPath): \(error)".utf8))
        }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return Result(status: task.terminationStatus, stdout: oData, stderr: eData)
    }
}
