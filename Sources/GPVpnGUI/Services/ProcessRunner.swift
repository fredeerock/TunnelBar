import Foundation

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs an external process, optionally feeding it data on stdin, and returns
/// its exit status together with captured output. stdout/stderr are read
/// concurrently to avoid pipe-buffer deadlocks on large output.
enum ProcessRunner {
    static func run(_ launchPath: String, _ args: [String], input: String?) throws -> ProcessResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let inPipe = Pipe()
        if input != nil {
            proc.standardInput = inPipe
        }

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "ProcessRunner.read", attributes: .concurrent)

        try proc.run()

        if let input = input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            inPipe.fileHandleForWriting.closeFile()
        }

        group.enter()
        queue.async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        queue.async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        proc.waitUntilExit()
        group.wait()

        return ProcessResult(
            status: proc.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
