import Foundation

public struct CommandResult: Equatable, Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum CommandRunnerError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
}

public protocol CommandRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let termination = ProcessTermination()
        let stdoutReader = PipeReader(stdout.fileHandleForReading)
        let stderrReader = PipeReader(stderr.fileHandleForReading)
        let stdoutTask = Task.detached { stdoutReader.readToEnd() }
        let stderrTask = Task.detached { stderrReader.readToEnd() }

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { completedProcess in
            Task {
                let result = CommandResult(
                    stdout: await stdoutTask.value,
                    stderr: await stderrTask.value,
                    exitCode: completedProcess.terminationStatus
                )
                await termination.finish(with: result)
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            _ = await stdoutTask.value
            _ = await stderrTask.value
            throw CommandRunnerError.launchFailed
        }

        return try await withTaskCancellationHandler(
            operation: {
                try await withThrowingTaskGroup(of: CommandResult.self) { group in
                    group.addTask {
                        await termination.wait()
                    }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        throw CommandRunnerError.timedOut
                    }

                    do {
                        guard let firstResult = try await group.next() else {
                            throw CommandRunnerError.launchFailed
                        }
                        group.cancelAll()
                        return firstResult
                    } catch {
                        group.cancelAll()
                        terminateIfRunning(process)
                        throw error
                    }
                }
            },
            onCancel: {
                terminateIfRunning(process)
            })
    }
}

private actor ProcessTermination {
    private var result: CommandResult?
    private var continuation: CheckedContinuation<CommandResult, Never>?

    func wait() async -> CommandResult {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with result: CommandResult) {
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private func terminateIfRunning(_ process: Process) {
    if process.isRunning {
        process.terminate()
    }
}

private final class PipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle

    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func readToEnd() -> Data {
        fileHandle.readDataToEndOfFile()
    }
}
