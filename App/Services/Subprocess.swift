import Foundation

/// Runs subprocesses as the user (hdiutil, diskutil info, wimlib…).
/// Root formatting does NOT go through here: it goes through the XPC helper.
public enum Subprocess {

    public struct Result {
        public let status: Int32
        public let stdout: Data
        public let stderr: Data

        public var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
        public var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
        public var succeeded: Bool { status == 0 }
        /// Preferred error message: stderr, or stdout if it's empty.
        public var errorMessage: String {
            let e = stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            let o = stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            return e.isEmpty ? o : e
        }
    }

    /// Runs and captures output synchronously.
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
                          stderr: Data("Couldn't run \(launchPath): \(error)".utf8))
        }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return Result(status: task.terminationStatus, stdout: oData, stderr: eData)
    }
}
