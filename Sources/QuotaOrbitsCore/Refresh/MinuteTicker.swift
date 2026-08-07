import Foundation

public protocol RefreshTicking: Sendable {
    func ticks(every interval: Duration) -> AsyncStream<Void>
}

@_spi(Testing)
public protocol RefreshTimeoutScheduling: Sendable {
    func wait(for duration: Duration, source: SourceKind) async throws
}

public struct MinuteTicker: RefreshTicking {
    public init() {}

    public func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let clock = ContinuousClock()
                var next = clock.now

                while !Task.isCancelled {
                    continuation.yield(())
                    next = next.advanced(by: interval)
                    do {
                        try await clock.sleep(until: next)
                    } catch {
                        break
                    }
                    if clock.now > next.advanced(by: interval) {
                        next = clock.now
                    }
                }

                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct ContinuousRefreshTimeoutScheduler: RefreshTimeoutScheduling {
    func wait(for duration: Duration, source: SourceKind) async throws {
        try await Task.sleep(for: duration)
    }
}
