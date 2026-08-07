import Foundation

public enum ClaudeQuotaError: Error, Equatable, Sendable {
    case commandFailed(exitCode: Int32)
    case invalidResponse
    case expectedTwoAccounts(actual: Int)
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
        guard payload.accounts.count >= 2 else {
            throw ClaudeQuotaError.expectedTwoAccounts(actual: payload.accounts.count)
        }

        return payload.accounts.prefix(2).map { account in
            ClaudeAccountQuota(
                id: String(account.number),
                alias: account.alias?.isEmpty == false
                    ? account.alias!
                    : String(format: "%02d", account.number),
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
            guard let date = ISO8601DateFormatter.quotaDate.date(from: value) else {
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

private extension ISO8601DateFormatter {
    static let quotaDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
