import Darwin
import Foundation

public actor ClaudeUsageTerminalSession: ClaudeUsageTerminalRunning {
    public init() {}

    public func captureUsage(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
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
                        arguments: arguments,
                        workingDirectory: workingDirectory
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

@_spi(Testing)
public enum ClaudeUsageTerminalAction: Equatable, Sendable {
    case acceptWorkspaceTrust
    case requestUsage
    case usageComplete
    case usageUnavailable
}

@_spi(Testing)
public struct ClaudeUsageTerminalConversation: Sendable {
    private enum Phase: Equatable, Sendable {
        case waitingForPrompt
        case waitingForTrustSubmission
        case waitingForPromptAfterTrust
        case waitingForUsage
        case complete
    }

    private var phase = Phase.waitingForPrompt
    private var tail = Data()

    public init() {}

    public mutating func receive(_ data: Data) -> ClaudeUsageTerminalAction? {
        tail.append(data)
        if tail.count > 1_024 {
            tail = tail.suffix(1_024)
        }
        let decoded = String(decoding: tail, as: UTF8.self)
        let searchable = Self.searchableText(decoded)

        switch phase {
        case .waitingForPrompt where Self.isWorkspaceTrustScreen(searchable, raw: decoded):
            phase = .waitingForTrustSubmission
            tail.removeAll(keepingCapacity: true)
            return .acceptWorkspaceTrust
        case .waitingForPrompt where decoded.contains("❯"):
            phase = .waitingForUsage
            tail.removeAll(keepingCapacity: true)
            return .requestUsage
        case .waitingForPromptAfterTrust where decoded.contains("❯"):
            phase = .waitingForUsage
            tail.removeAll(keepingCapacity: true)
            return .requestUsage
        case .waitingForUsage
        where searchable.contains("esctoexit") || searchable.contains("esctogoback"):
            phase = .complete
            return .usageComplete
        case .waitingForUsage
        where searchable.contains("usageendpointisratelimited"):
            phase = .complete
            return .usageUnavailable
        case .waitingForPrompt, .waitingForTrustSubmission, .waitingForPromptAfterTrust,
            .waitingForUsage, .complete:
            return nil
        }
    }

    public mutating func didSubmitWorkspaceTrustAcceptance() {
        guard phase == .waitingForTrustSubmission else { return }
        phase = .waitingForPromptAfterTrust
        tail.removeAll(keepingCapacity: true)
    }

    private static func isWorkspaceTrustScreen(_ value: String, raw: String) -> Bool {
        value.contains("workspace")
            && value.contains("trust")
            && value.contains("security")
            && value.contains("folder")
            && value.contains("yes")
            && raw.contains("❯")
    }

    private static func searchableText(_ value: String) -> String {
        let pattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let stripped =
            (try? NSRegularExpression(pattern: pattern))?
            .stringByReplacingMatches(in: value, range: range, withTemplate: "")
            ?? value
        let scalars = stripped.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }
}

private func captureTranscript(
    state: PTYSessionState,
    executable: URL,
    arguments: [String],
    workingDirectory: URL
) async throws -> Data {
    try state.start(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory
    )

    while true {
        try Task.checkCancellation()
        switch state.status {
        case .waitingForPrompt:
            try await Task.sleep(for: .milliseconds(20))
        case .readyToAcceptTrust:
            try state.write(Data("\u{1B}[B".utf8))
            state.markWorkspaceTrustOptionSelected()
        case .readyToConfirmTrust:
            try await Task.sleep(for: .milliseconds(250))
            try state.write(Data("\r".utf8))
            state.markWorkspaceTrustAccepted()
        case .readyForUsage:
            try state.write(Data("/usage\r".utf8))
            state.markUsageRequested()
        case .capturing:
            try await Task.sleep(for: .milliseconds(20))
        case .usageComplete:
            let transcript = state.transcript
            try state.write(Data("\u{1B}\r".utf8))
            try await Task.sleep(for: .milliseconds(50))
            try state.write(Data("/exit\r".utf8))
            return transcript
        case .usageUnavailable:
            throw ClaudeUsageTerminalError.usageUnavailable
        case .outputTooLarge:
            throw ClaudeUsageTerminalError.outputTooLarge
        case .exited:
            throw ClaudeUsageTerminalError.sessionClosed
        }
    }
}

private final class PTYSessionState: @unchecked Sendable {
    enum Status {
        case waitingForPrompt
        case readyToAcceptTrust
        case readyToConfirmTrust
        case readyForUsage
        case capturing
        case usageComplete
        case usageUnavailable
        case outputTooLarge
        case exited
    }

    private let lock = NSLock()
    private let maximumOutputBytes: Int
    private var buffer = Data()
    private var conversation = ClaudeUsageTerminalConversation()
    private var currentStatus = Status.waitingForPrompt
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

    func start(
        executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) throws {
        do {
            try FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ClaudeUsageTerminalError.launchFailed
        }
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
        child.currentDirectoryURL = workingDirectory
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

    func markUsageRequested() {
        lock.withLock {
            if currentStatus == .readyForUsage {
                currentStatus = .capturing
            }
        }
    }

    func markWorkspaceTrustAccepted() {
        lock.withLock {
            if currentStatus == .readyToConfirmTrust {
                conversation.didSubmitWorkspaceTrustAcceptance()
                currentStatus = .waitingForPrompt
            }
        }
    }

    func markWorkspaceTrustOptionSelected() {
        lock.withLock {
            if currentStatus == .readyToAcceptTrust {
                currentStatus = .readyToConfirmTrust
            }
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
            guard
                currentStatus == .waitingForPrompt
                    || currentStatus == .readyToAcceptTrust
                    || currentStatus == .readyToConfirmTrust
                    || currentStatus == .readyForUsage
                    || currentStatus == .capturing
            else { return }
            guard buffer.count + data.count <= maximumOutputBytes else {
                currentStatus = .outputTooLarge
                return
            }
            buffer.append(data)
            switch conversation.receive(data) {
            case .acceptWorkspaceTrust:
                currentStatus = .readyToAcceptTrust
            case .requestUsage:
                currentStatus = .readyForUsage
            case .usageComplete:
                currentStatus = .usageComplete
            case .usageUnavailable:
                currentStatus = .usageUnavailable
            case nil:
                break
            }
        }
    }

    private func markExited() {
        lock.withLock {
            if currentStatus == .waitingForPrompt
                || currentStatus == .readyToAcceptTrust
                || currentStatus == .readyToConfirmTrust
                || currentStatus == .readyForUsage
                || currentStatus == .capturing
            {
                currentStatus = .exited
            }
        }
    }
}
