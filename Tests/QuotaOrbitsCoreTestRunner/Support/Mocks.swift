import Foundation
@_spi(Testing) import QuotaOrbitsCore

struct ScriptedSentMessage: Equatable, Sendable {
    let method: String?
    let id: Int?
    let clientName: String?
    let clientTitle: String?
    let clientVersion: String?
}

actor MockCommandRunner: CommandRunning {
    let result: CommandResult
    private(set) var lastExecutable: URL?
    private(set) var lastArguments: [String]?

    init(result: CommandResult) {
        self.result = result
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> CommandResult {
        lastExecutable = executable
        lastArguments = arguments
        return result
    }
}

actor ScriptedJSONLineTransport: JSONLineTransport {
    enum Outcome: Sendable {
        case line(Data)
        case closed
    }

    private var outcomes: [Outcome]
    private var ready: [Outcome] = []
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private var sent: [Data] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var isStarted = false

    init(responses: [Data]) {
        self.outcomes = responses.map(Outcome.line)
    }

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func start() async throws {
        startCount += 1
        isStarted = true
    }

    func send(_ line: Data) async throws {
        guard isStarted else { throw JSONLineTransportError.transportClosed }
        sent.append(line)

        guard requestID(in: line) != nil, !outcomes.isEmpty else { return }
        let outcome = outcomes.removeFirst()
        if let waiter = waiters.first {
            waiters.removeFirst()
            resume(waiter, with: outcome)
        } else {
            ready.append(outcome)
        }
    }

    func nextLine() async throws -> Data {
        guard isStarted else { throw JSONLineTransportError.transportClosed }
        if !ready.isEmpty {
            return try resolve(ready.removeFirst())
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func stop() async {
        stopCount += 1
        isStarted = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: JSONLineTransportError.transportClosed) }
    }

    func sentMessages() -> [ScriptedSentMessage] {
        sent.compactMap {
            guard
                let object = try? JSONSerialization.jsonObject(with: $0)
                    as? [String: Any]
            else { return nil }
            let params = object["params"] as? [String: Any]
            let clientInfo = params?["clientInfo"] as? [String: Any]
            return ScriptedSentMessage(
                method: object["method"] as? String,
                id: object["id"] as? Int,
                clientName: clientInfo?["name"] as? String,
                clientTitle: clientInfo?["title"] as? String,
                clientVersion: clientInfo?["version"] as? String
            )
        }
    }

    private func requestID(in line: Data) -> Int? {
        let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        return object?["id"] as? Int
    }

    private func resolve(_ outcome: Outcome) throws -> Data {
        switch outcome {
        case let .line(line): return line
        case .closed: throw JSONLineTransportError.transportClosed
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<Data, Error>,
        with outcome: Outcome
    ) {
        switch outcome {
        case let .line(line): continuation.resume(returning: line)
        case .closed: continuation.resume(throwing: JSONLineTransportError.transportClosed)
        }
    }
}

actor DelayingJSONLineTransport: JSONLineTransport {
    private let delayedRequestID: Int
    private var sentIDs: [Int] = []
    private var ready: [Data] = []
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private var isStarted = false

    init(delayedRequestID: Int) {
        self.delayedRequestID = delayedRequestID
    }

    func start() async throws {
        isStarted = true
    }

    func send(_ line: Data) async throws {
        guard isStarted else { throw JSONLineTransportError.transportClosed }
        let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        guard let id = object?["id"] as? Int else { return }
        if id == delayedRequestID {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        sentIDs.append(id)
        let response = Data(#"{"id":\#(id),"result":{}}"#.utf8)
        if !waiters.isEmpty {
            waiters.removeFirst().resume(returning: response)
        } else {
            ready.append(response)
        }
    }

    func nextLine() async throws -> Data {
        guard isStarted else { throw JSONLineTransportError.transportClosed }
        if !ready.isEmpty { return ready.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func stop() async {
        isStarted = false
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: JSONLineTransportError.transportClosed) }
    }

    func sentRequestIDs() -> [Int] {
        sentIDs
    }
}

enum FixtureQuotaFetchError: Error, Sendable {
    case fixture(String)
}

actor ManualRefreshTimeoutScheduler: RefreshTimeoutScheduling {
    private var nextID = 0
    private var waiters: [Int: (SourceKind, CheckedContinuation<Void, Error>)] = [:]
    private var scheduleWaiters: [(SourceKind, CheckedContinuation<Void, Never>)] = []

    func wait(for duration: Duration, source: SourceKind) async throws {
        nextID += 1
        let id = nextID
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = (source, continuation)
                resumeScheduleWaiters(for: source)
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func waitUntilScheduled(for source: SourceKind) async {
        if waiters.values.contains(where: { $0.0 == source }) { return }
        await withCheckedContinuation { continuation in
            scheduleWaiters.append((source, continuation))
        }
    }

    func fire(_ source: SourceKind) {
        let matching = waiters.filter { $0.value.0 == source }
        matching.keys.forEach { waiters.removeValue(forKey: $0) }
        matching.values.forEach { $0.1.resume(returning: ()) }
    }

    private func cancel(id: Int) {
        waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
    }

    private func resumeScheduleWaiters(for source: SourceKind) {
        let ready = scheduleWaiters.filter { $0.0 == source }
        scheduleWaiters.removeAll { $0.0 == source }
        ready.forEach { $0.1.resume() }
    }
}

final class ManualRefreshTicker: RefreshTicking, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Void>.Continuation?

    func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.yield(())
        }
    }

    func yield() {
        lock.lock()
        let continuation = continuation
        lock.unlock()
        continuation?.yield(())
    }

    func finish() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}
