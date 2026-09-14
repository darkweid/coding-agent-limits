import Foundation

public enum ClaudeUsageTerminalError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
    case outputTooLarge
    case sessionClosed
    case usageUnavailable
}

public protocol ClaudeUsageTerminalRunning: Sendable {
    func captureUsage(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Data
}
