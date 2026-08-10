import Foundation

public struct IntervalTicker: RefreshTicking {
    public init() {}

    public func ticks(every interval: Duration) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    do {
                        try await clock.sleep(for: interval)
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
