import Foundation

public protocol JSONLineTransport: Sendable {
    func start() async throws
    func send(_ line: Data) async throws
    func nextLine() async throws -> Data
    func stop() async
}

public enum JSONLineTransportError: Error, Equatable, Sendable {
    case failedToStart
    case lineTooLong
    case transportClosed
}

@_spi(Testing)
public struct OrderedOutputChunks: Sendable {
    public let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    public init() {
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        stream = pair.stream
        continuation = pair.continuation
    }

    public func yield(_ data: Data) {
        continuation.yield(data)
    }

    public func finish() {
        continuation.finish()
    }
}

public actor ProcessJSONLineTransport: JSONLineTransport {
    private static let maximumLineLength = 1_048_576

    private let executable: URL
    private let arguments: [String]
    private var process: Process?
    private var standardInput: FileHandle?
    private var standardOutput: FileHandle?
    private var standardError: FileHandle?
    private var outputChunks: OrderedOutputChunks?
    private var outputTask: Task<Void, Never>?
    private var buffer = Data()
    private var lines: [Data] = []
    private var readers: [CheckedContinuation<Data, Error>] = []
    private var isClosed = true

    public init() {
        self.executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        self.arguments = ["app-server"]
    }

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public func start() async throws {
        if process?.isRunning == true { return }
        cleanUpHandles(terminate: false)

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let output = outputPipe.fileHandleForReading
        let error = errorPipe.fileHandleForReading
        let chunks = OrderedOutputChunks()
        self.process = process
        standardInput = inputPipe.fileHandleForWriting
        standardOutput = output
        standardError = error
        outputChunks = chunks
        buffer.removeAll(keepingCapacity: true)
        lines.removeAll(keepingCapacity: true)
        isClosed = false

        outputTask = Task { [weak self, weak process] in
            for await data in chunks.stream {
                await self?.receivedStandardOutput(data, from: process)
            }
            await self?.standardOutputFinished(from: process)
        }
        output.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                chunks.finish()
            } else {
                chunks.yield(data)
            }
        }
        error.readabilityHandler = { handle in
            _ = handle.availableData
        }
        do {
            try process.run()
        } catch {
            isClosed = true
            cleanUpHandles(terminate: false)
            finishReaders(with: JSONLineTransportError.failedToStart)
            throw JSONLineTransportError.failedToStart
        }
    }

    public func send(_ line: Data) async throws {
        guard !isClosed, let standardInput else {
            throw JSONLineTransportError.transportClosed
        }

        do {
            try standardInput.write(contentsOf: line)
            try standardInput.write(contentsOf: Data([0x0A]))
        } catch {
            close(with: .transportClosed, terminate: true)
            throw JSONLineTransportError.transportClosed
        }
    }

    public func nextLine() async throws -> Data {
        if !lines.isEmpty {
            return lines.removeFirst()
        }
        guard !isClosed else {
            throw JSONLineTransportError.transportClosed
        }
        return try await withCheckedThrowingContinuation { continuation in
            readers.append(continuation)
        }
    }

    public func stop() async {
        close(with: .transportClosed, terminate: true)
        lines.removeAll(keepingCapacity: false)
    }

    private func receivedStandardOutput(_ data: Data, from child: Process?) {
        guard child === process, !isClosed else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard line.count <= Self.maximumLineLength else {
                close(with: .lineTooLong, terminate: true)
                return
            }
            yield(line)
        }

        if buffer.count > Self.maximumLineLength {
            close(with: .lineTooLong, terminate: true)
        }
    }

    private func standardOutputFinished(from child: Process?) {
        guard child === process, !isClosed else { return }
        close(with: .transportClosed, terminate: true)
    }

    private func yield(_ line: Data) {
        if !readers.isEmpty {
            readers.removeFirst().resume(returning: line)
        } else {
            lines.append(line)
        }
    }

    private func close(
        with error: JSONLineTransportError,
        terminate: Bool
    ) {
        guard !isClosed || process != nil else { return }
        isClosed = true
        cleanUpHandles(terminate: terminate)
        buffer.removeAll(keepingCapacity: false)
        finishReaders(with: error)
    }

    private func cleanUpHandles(terminate: Bool) {
        standardOutput?.readabilityHandler = nil
        standardError?.readabilityHandler = nil
        process?.terminationHandler = nil
        outputChunks?.finish()
        outputTask?.cancel()
        try? standardInput?.close()
        try? standardOutput?.close()
        try? standardError?.close()
        if terminate, process?.isRunning == true {
            process?.terminate()
        }
        standardInput = nil
        standardOutput = nil
        standardError = nil
        outputChunks = nil
        outputTask = nil
        process = nil
    }

    private func finishReaders(with error: JSONLineTransportError) {
        let pending = readers
        readers.removeAll()
        pending.forEach { $0.resume(throwing: error) }
    }
}
