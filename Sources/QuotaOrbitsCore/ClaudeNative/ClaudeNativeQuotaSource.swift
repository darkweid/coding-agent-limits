import Foundation

public enum ClaudeNativeQuotaError: Error, Equatable, Sendable {
    case terminalUnavailable
    case invalidResponse
}

public struct ClaudeNativeQuotaSource: ClaudeQuotaFetching {
    public let executable: URL
    private let terminalRunner: any ClaudeUsageTerminalRunning
    private let workingDirectory: URL
    private let parser: ClaudeUsageTerminalParser
    private let now: @Sendable () -> Date

    public init(
        executable: URL,
        terminalRunner: any ClaudeUsageTerminalRunning = ClaudeUsageTerminalSession(),
        workingDirectory: URL? = nil,
        parser: ClaudeUsageTerminalParser = ClaudeUsageTerminalParser(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.executable = executable
        self.terminalRunner = terminalRunner
        self.workingDirectory = workingDirectory ?? Self.defaultWorkingDirectory()
        self.parser = parser
        self.now = now
    }

    public func fetch() async throws -> [ClaudeAccountQuota] {
        let transcript: Data
        do {
            transcript = try await terminalRunner.captureUsage(
                executable: executable,
                arguments: ["--permission-mode", "plan"],
                workingDirectory: workingDirectory,
                timeout: .seconds(10),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )
        } catch {
            throw ClaudeNativeQuotaError.terminalUnavailable
        }

        let usage: ClaudeNativeUsage
        do {
            usage = try parser.parse(transcript, now: now())
        } catch {
            throw ClaudeNativeQuotaError.invalidResponse
        }

        return [
            ClaudeAccountQuota(
                id: "native",
                alias: "native",
                isActive: true,
                fiveHour: usage.fiveHour,
                weekly: usage.weekly,
                scoped: usage.scoped
            )
        ]
    }

    private static func defaultWorkingDirectory() -> URL {
        let fileManager = FileManager.default
        let applicationSupport =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        return
            applicationSupport
            .appendingPathComponent("Coding Agent Limits", isDirectory: true)
            .appendingPathComponent("Claude Session", isDirectory: true)
    }
}
