import Foundation

public enum ClaudeCodeQuotaError: Error, Equatable, Sendable {
    case terminalUnavailable
    case invalidResponse
}

public struct ClaudeCodeQuotaSource: QuotaSource {
    public let sourceID = QuotaSourceID.claudeCode
    public let providerID = ProviderID.claude
    public let executable: URL
    private let terminalRunner: any ClaudeUsageTerminalRunning
    private let parser: ClaudeUsageTerminalParser
    private let now: @Sendable () -> Date

    public init(
        executable: URL,
        terminalRunner: any ClaudeUsageTerminalRunning = ClaudeUsageTerminalSession(),
        parser: ClaudeUsageTerminalParser = ClaudeUsageTerminalParser(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.executable = executable
        self.terminalRunner = terminalRunner
        self.parser = parser
        self.now = now
    }

    public func fetch() async throws -> ProviderQuota {
        let transcript: Data
        do {
            transcript = try await terminalRunner.captureUsage(
                executable: executable,
                arguments: ["--permission-mode", "plan"],
                timeout: .seconds(10),
                maximumOutputBytes: ClaudeUsageTerminalParser.maximumOutputBytes
            )
        } catch {
            throw ClaudeCodeQuotaError.terminalUnavailable
        }

        let limits: [QuotaLimit]
        do {
            limits = try parser.parse(transcript, now: now())
        } catch {
            throw ClaudeCodeQuotaError.invalidResponse
        }

        return ProviderQuota(
            providerID: providerID,
            accounts: [
                QuotaAccount(
                    id: "active",
                    alias: "",
                    isActive: true,
                    state: .fresh,
                    limits: limits
                )
            ]
        )
    }
}
