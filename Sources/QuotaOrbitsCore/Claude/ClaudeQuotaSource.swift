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
            let selected = account.selectedUsage
            return ClaudeAccountQuota(
                id: String(account.number),
                alias: alias,
                isActive: account.active,
                fiveHour: selected.usage?.fiveHour.map(Self.quotaWindow(from:)),
                weekly: selected.usage?.sevenDay.map(Self.quotaWindow(from:)),
                scoped: (selected.usage?.scoped ?? []).compactMap(Self.scopedQuota(from:)),
                state: selected.state
            )
        }
    }

    private static func quotaWindow(from window: ClaudeUsageWindow) -> QuotaWindow {
        QuotaWindow(usedPercent: window.pct, resetsAt: window.resetsAt)
    }

    private static func scopedQuota(
        from scoped: ClaudeScopedUsageWindow
    ) -> ClaudeScopedQuota? {
        let label = scoped.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = label.lowercased()
        guard !label.isEmpty,
            label.count <= 40,
            !label.contains("@"),
            !["claude", "codex"].contains(where: lowered.contains),
            label.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else { return nil }

        return ClaudeScopedQuota(
            label: label,
            window: QuotaWindow(
                usedPercent: scoped.pct,
                resetsAt: scoped.resetsAt
            )
        )
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
    let usage: ClaudeUsage?
    let lastGoodUsage: ClaudeUsage?
    let lastGoodFetchedAt: Date?

    var selectedUsage: (usage: ClaudeUsage?, state: ClaudeAccountQuotaState) {
        if let usage {
            return (usage, .fresh)
        }
        if let lastGoodUsage, let lastGoodFetchedAt {
            return (lastGoodUsage, .stale(lastSuccessAt: lastGoodFetchedAt))
        }
        return (nil, .unavailable)
    }
}

private struct ClaudeUsage: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?
    let scoped: [ClaudeScopedUsageWindow]?
}

private struct ClaudeUsageWindow: Decodable {
    let pct: Double
    let resetsAt: Date?
}

private struct ClaudeScopedUsageWindow: Decodable {
    let name: String
    let pct: Double
    let resetsAt: Date?
}
