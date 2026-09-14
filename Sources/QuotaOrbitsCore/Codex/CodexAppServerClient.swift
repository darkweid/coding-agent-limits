import Foundation

public enum CodexAppServerError: Error, Equatable, Sendable {
    case protocolError
    case timedOut
    case transportClosed
}

public actor CodexAppServerClient {
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private struct OutboundWrite {
        let line: Data
        let requestID: Int?
        let completion: CheckedContinuation<Void, Error>?
    }

    private struct ResponseHeader: Decodable {
        struct RPCError: Decodable {}

        let id: Int?
        let error: RPCError?
    }

    private let transport: any JSONLineTransport
    private let clock = ContinuousClock()
    private var nextRequestID = 1
    private var pending: [Int: PendingRequest] = [:]
    private var outboundWrites: [OutboundWrite] = []
    private var writerTask: Task<Void, Never>?
    private var writerGeneration = 0
    private var readTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Error>?
    private var isInitialized = false

    public init() {
        self.transport = ProcessJSONLineTransport()
    }

    public init(transport: any JSONLineTransport) {
        self.transport = transport
    }

    public func rateLimitsResponse() async throws -> Data {
        let deadline = clock.now.advanced(by: .seconds(10))
        do {
            try await ensureInitialized(deadline: deadline)
            return try await request(
                method: "account/rateLimits/read",
                params: [:],
                deadline: deadline
            )
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            await failConnection(with: .transportClosed)
            throw CodexAppServerError.transportClosed
        }
    }

    private func ensureInitialized(
        deadline: ContinuousClock.Instant
    ) async throws {
        if isInitialized { return }
        if let initializationTask {
            try await initializationTask.value
            return
        }

        let task = Task {
            try await self.initialize(deadline: deadline)
        }
        initializationTask = task
        do {
            try await task.value
            isInitialized = true
            initializationTask = nil
        } catch {
            initializationTask = nil
            throw error
        }
    }

    private func initialize(deadline: ContinuousClock.Instant) async throws {
        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "quota_orbits",
                    "title": "Coding Agent Limits",
                    "version": "0.1.0",
                ]
            ],
            deadline: deadline
        )
        try await sendNotification(method: "initialized", params: [:])
    }

    private func request(
        method: String,
        params: [String: Any],
        deadline: ContinuousClock.Instant
    ) async throws -> Data {
        try await ensureConnection()
        guard clock.now < deadline else {
            await failConnection(with: .timedOut)
            throw CodexAppServerError.timedOut
        }

        let id = nextRequestID
        nextRequestID += 1
        let line = try makeLine(method: method, id: id, params: params)
        let remaining = clock.now.duration(to: deadline)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: remaining)
                        await self?.requestTimedOut(id)
                    } catch {}
                }
                pending[id] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
                enqueueWrite(line, requestID: id)
            }
        } onCancel: {
            Task { await self.cancelRequest(id) }
        }
    }

    private func sendNotification(
        method: String,
        params: [String: Any]
    ) async throws {
        let line = try makeLine(method: method, id: nil, params: params)
        do {
            try await withCheckedThrowingContinuation { continuation in
                enqueueWrite(
                    line,
                    requestID: nil,
                    completion: continuation
                )
            }
        } catch {
            await failConnection(with: .transportClosed)
            throw CodexAppServerError.transportClosed
        }
    }

    private func ensureConnection() async throws {
        if readTask != nil { return }
        do {
            try await transport.start()
        } catch {
            await transport.stop()
            throw CodexAppServerError.transportClosed
        }
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        do {
            while !Task.isCancelled {
                let line = try await transport.nextLine()
                try await receive(line)
            }
        } catch let error as CodexAppServerError {
            if !Task.isCancelled {
                await failConnection(with: error)
            }
        } catch {
            if !Task.isCancelled {
                await failConnection(with: .transportClosed)
            }
        }
    }

    private func receive(_ line: Data) async throws {
        let header: ResponseHeader
        do {
            header = try JSONDecoder().decode(ResponseHeader.self, from: line)
        } catch {
            throw CodexAppServerError.protocolError
        }

        guard let id = header.id else { return }
        guard header.error == nil else {
            throw CodexAppServerError.protocolError
        }
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(returning: line)
    }

    private func enqueueWrite(
        _ line: Data,
        requestID: Int?,
        completion: CheckedContinuation<Void, Error>? = nil
    ) {
        outboundWrites.append(
            OutboundWrite(
                line: line,
                requestID: requestID,
                completion: completion
            )
        )
        guard writerTask == nil else { return }
        writerGeneration += 1
        let generation = writerGeneration
        writerTask = Task { [weak self] in
            await self?.drainWrites(generation: generation)
        }
    }

    private func drainWrites(generation: Int) async {
        while generation == writerGeneration, !outboundWrites.isEmpty {
            let write = outboundWrites.removeFirst()
            if let requestID = write.requestID, pending[requestID] == nil {
                continue
            }
            do {
                try await transport.send(write.line)
                guard generation == writerGeneration else {
                    write.completion?.resume(
                        throwing: CodexAppServerError.transportClosed
                    )
                    return
                }
                write.completion?.resume(returning: ())
            } catch {
                write.completion?.resume(
                    throwing: CodexAppServerError.transportClosed
                )
                await failConnection(with: .transportClosed)
                return
            }
        }
        if generation == writerGeneration {
            writerTask = nil
        }
    }

    private func requestTimedOut(_ id: Int) async {
        guard pending[id] != nil else { return }
        await failConnection(with: .timedOut)
    }

    private func cancelRequest(_ id: Int) async {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeoutTask.cancel()
        request.continuation.resume(throwing: CodexAppServerError.transportClosed)
        await failConnection(with: .transportClosed)
    }

    private func failConnection(with error: CodexAppServerError) async {
        isInitialized = false
        readTask?.cancel()
        readTask = nil
        writerGeneration += 1
        writerTask?.cancel()
        writerTask = nil

        let queuedWrites = outboundWrites
        outboundWrites.removeAll()
        for write in queuedWrites {
            write.completion?.resume(throwing: error)
        }

        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.timeoutTask.cancel()
            request.continuation.resume(throwing: error)
        }
        await transport.stop()
    }

    private func makeLine(
        method: String,
        id: Int?,
        params: [String: Any]
    ) throws -> Data {
        var object: [String: Any] = ["method": method, "params": params]
        if let id { object["id"] = id }
        do {
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw CodexAppServerError.protocolError
        }
    }
}
