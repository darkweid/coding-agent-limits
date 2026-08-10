import Foundation

public enum ClaudeQuotaError: Error, Equatable, Sendable {
    case commandFailed(exitCode: Int32)
    case invalidResponse
}

public struct ClaudeQuotaSource: ClaudeQuotaFetching {
    public let executable: URL
    private let runner: any CommandRunning

    public init(
        executable: URL,
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.executable = executable
        self.runner = runner
    }

    public func fetch() async throws -> [ClaudeAccountQuota] {
        let result = try await runner.run(
            executable: executable,
            arguments: ["list", "--json"],
            timeout: .seconds(10)
        )
        guard result.exitCode == 0 else {
            throw ClaudeQuotaError.commandFailed(exitCode: result.exitCode)
        }

        let payload = try ClaudePayload.decode(result.stdout)
        guard !payload.accounts.isEmpty else {
            throw ClaudeQuotaError.invalidResponse
        }

        return payload.accounts.map { account in
            let alias =
                account.alias.flatMap { value in
                    value.isEmpty ? nil : value
                } ?? String(format: "%02d", account.number)
            return ClaudeAccountQuota(
                id: String(account.number),
                alias: alias,
                isActive: account.active,
                fiveHour: QuotaWindow(
                    usedPercent: account.usage.fiveHour.pct,
                    resetsAt: account.usage.fiveHour.resetsAt
                ),
                weekly: QuotaWindow(
                    usedPercent: account.usage.sevenDay.pct,
                    resetsAt: account.usage.sevenDay.resetsAt
                )
            )
        }
    }
}

private struct ClaudePayload: Decodable {
    let accounts: [ClaudeAccount]

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseReset(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected ISO-8601 date"
                )
            }
            return date
        }

        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            throw ClaudeQuotaError.invalidResponse
        }
    }

    private static func parseReset(_ value: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let wholeSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? fractional.parse(value) {
            return date
        }
        return try? wholeSeconds.parse(value)
    }
}

private struct ClaudeAccount: Decodable {
    let number: Int
    let alias: String?
    let active: Bool
    let usage: ClaudeUsage
}

private struct ClaudeUsage: Decodable {
    let fiveHour: ClaudeUsageWindow
    let sevenDay: ClaudeUsageWindow
}

private struct ClaudeUsageWindow: Decodable {
    let pct: Double
    let resetsAt: Date
}
