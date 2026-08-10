import Foundation

public protocol RefreshTicking: Sendable {
    func ticks(every interval: Duration) -> AsyncStream<Void>
}

@_spi(Testing)
public protocol RefreshTimeoutScheduling: Sendable {
    func wait(for duration: Duration, source: SourceKind) async throws
}

struct ContinuousRefreshTimeoutScheduler: RefreshTimeoutScheduling {
    func wait(for duration: Duration, source: SourceKind) async throws {
        try await Task.sleep(for: duration)
    }
}
