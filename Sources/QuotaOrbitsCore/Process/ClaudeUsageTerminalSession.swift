import Darwin
import Foundation

public actor ClaudeUsageTerminalSession: ClaudeUsageTerminalRunning {
    public init() {}

    public func captureUsage(
        executable: URL,
        arguments: [String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data {
        let state = PTYSessionState(maximumOutputBytes: maximumOutputBytes)
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask {
                    try await captureTranscript(
                        state: state,
                        executable: executable,
                        arguments: arguments
                    )
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ClaudeUsageTerminalError.timedOut
                }

                defer {
                    group.cancelAll()
                    state.stop()
                }
                guard let result = try await group.next() else {
                    throw ClaudeUsageTerminalError.sessionClosed
                }
                return result
            }
        } onCancel: {
            state.stop()
        }
    }
}

private func captureTranscript(
    state: PTYSessionState,
    executable: URL,
    arguments: [String]
) async throws -> Data {
    try state.start(executable: executable, arguments: arguments)
    try state.write(Data("/usage\r".utf8))

    while true {
        try Task.checkCancellation()
        switch state.status {
        case .capturing:
            try await Task.sleep(for: .milliseconds(20))
        case .usageComplete:
            let transcript = state.transcript
            try state.write(Data("\u{1B}\r".utf8))
            try await Task.sleep(for: .milliseconds(50))
            try state.write(Data("/exit\r".utf8))
            return transcript
        case .outputTooLarge:
            throw ClaudeUsageTerminalError.outputTooLarge
        case .exited:
            throw ClaudeUsageTerminalError.sessionClosed
        }
    }
}

private final class PTYSessionState: @unchecked Sendable {
    enum Status {
        case capturing
        case usageComplete
        case outputTooLarge
        case exited
    }

    private let lock = NSLock()
    private let maximumOutputBytes: Int
    private var buffer = Data()
    private var currentStatus = Status.capturing
    private var process: Process?
    private var masterHandle: FileHandle?
    private var slaveHandle: FileHandle?

    init(maximumOutputBytes: Int) {
        self.maximumOutputBytes = maximumOutputBytes
    }

    var status: Status {
        lock.withLock { currentStatus }
    }

    var transcript: Data {
        lock.withLock { buffer }
    }

    func start(executable: URL, arguments: [String]) throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        guard openpty(&masterDescriptor, &slaveDescriptor, nil, nil, nil) == 0 else {
            throw ClaudeUsageTerminalError.launchFailed
        }

        let master = FileHandle(fileDescriptor: masterDescriptor, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveDescriptor, closeOnDealloc: true)
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["NO_COLOR"] = "1"
        child.environment = environment
        child.standardInput = slave
        child.standardOutput = slave
        child.standardError = slave
        child.terminationHandler = { [weak self] _ in
            self?.markExited()
        }
        master.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData)
        }

        lock.withLock {
            process = child
            masterHandle = master
            slaveHandle = slave
        }
        do {
            try child.run()
        } catch {
            stop()
            throw ClaudeUsageTerminalError.launchFailed
        }
    }

    func write(_ data: Data) throws {
        guard let handle = lock.withLock({ masterHandle }) else {
            throw ClaudeUsageTerminalError.sessionClosed
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw ClaudeUsageTerminalError.sessionClosed
        }
    }

    func stop() {
        let owned: (Process?, FileHandle?, FileHandle?) = lock.withLock {
            let result = (process, masterHandle, slaveHandle)
            process = nil
            masterHandle = nil
            slaveHandle = nil
            currentStatus = .exited
            return result
        }
        owned.1?.readabilityHandler = nil
        if let process = owned.0, process.isRunning {
            process.terminate()
        }
        try? owned.1?.close()
        try? owned.2?.close()
    }

    private func append(_ data: Data) {
        guard !data.isEmpty else {
            markExited()
            return
        }
        lock.withLock {
            guard currentStatus == .capturing else { return }
            guard buffer.count + data.count <= maximumOutputBytes else {
                currentStatus = .outputTooLarge
                return
            }
            buffer.append(data)
            if String(decoding: buffer.suffix(256), as: UTF8.self).contains("Esc to exit") {
                currentStatus = .usageComplete
            }
        }
    }

    private func markExited() {
        lock.withLock {
            if currentStatus == .capturing {
                currentStatus = .exited
            }
        }
    }
}
