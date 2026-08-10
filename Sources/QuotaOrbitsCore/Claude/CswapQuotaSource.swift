import Foundation

public enum CswapQuotaError: Error, Equatable, Sendable {
    case commandFailed(exitCode: Int32)
    case invalidResponse
}

public struct CswapQuotaSource: QuotaSource {
    public let sourceID = QuotaSourceID.cswap
    public let providerID = ProviderID.claude
    public let executable: URL
    private let runner: any CommandRunning

    public init(
        executable: URL,
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.executable = executable
        self.runner = runner
    }

    public func fetch() async throws -> ProviderQuota {
        let result = try await runner.run(
            executable: executable,
            arguments: ["list", "--json"],
            timeout: .seconds(10)
        )
        guard result.exitCode == 0 else {
            throw CswapQuotaError.commandFailed(exitCode: result.exitCode)
        }

        let payload = try CswapPayload.decode(result.stdout)
        guard payload.schemaVersion == 1, !payload.accounts.isEmpty else {
            throw CswapQuotaError.invalidResponse
        }

        return ProviderQuota(
            providerID: providerID,
            accounts: try payload.accounts.map(Self.account(from:))
        )
    }

    private static func account(from account: CswapAccount) throws -> QuotaAccount {
        let mappedUsage: (AccountDataState, [QuotaLimit])
        if let usage = account.usage {
            mappedUsage = (.fresh, try limits(from: usage))
        } else if let usage = account.lastGoodUsage,
            let fetchedAt = account.lastGoodFetchedAt.flatMap(parseDate)
        {
            mappedUsage = (.stale(lastSuccessAt: fetchedAt), try limits(from: usage))
        } else {
            mappedUsage = (.unavailable, [])
        }

        return QuotaAccount(
            id: String(account.number),
            alias: account.alias ?? "",
            isActive: account.active,
            state: mappedUsage.0,
            limits: mappedUsage.1
        )
    }

    private static func limits(from usage: CswapUsage) throws -> [QuotaLimit] {
        guard
            let fiveHour = limit(
                id: "five-hour",
                label: "5 hours",
                window: usage.fiveHour
            ),
            let weekly = limit(
                id: "weekly",
                label: "Weekly",
                window: usage.sevenDay
            )
        else {
            throw CswapQuotaError.invalidResponse
        }

        let scoped = try (usage.scoped ?? []).enumerated().map { index, window in
            let label = window.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidLabel(label),
                let quota = limit(
                    id: "scoped-\(index + 1)",
                    label: label,
                    window: window.asWindow
                )
            else {
                throw CswapQuotaError.invalidResponse
            }
            return quota
        }
        return [fiveHour, weekly] + scoped
    }

    private static func limit(
        id: String,
        label: String,
        window: CswapUsageWindow
    ) -> QuotaLimit? {
        guard
            window.pct.isFinite,
            (0...100).contains(window.pct),
            let resetsAt = parseDate(window.resetsAt)
        else {
            return nil
        }
        return QuotaLimit(
            id: id,
            label: label,
            usedPercent: window.pct,
            resetsAt: resetsAt
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let wholeSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        return (try? fractional.parse(value)) ?? (try? wholeSeconds.parse(value))
    }

    private static func isValidLabel(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 40
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

private struct CswapPayload: Decodable {
    let schemaVersion: Int
    let accounts: [CswapAccount]

    static func decode(_ data: Data) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw CswapQuotaError.invalidResponse
        }
    }
}

private struct CswapAccount: Decodable {
    let number: Int
    let alias: String?
    let active: Bool
    let usage: CswapUsage?
    let lastGoodUsage: CswapUsage?
    let lastGoodFetchedAt: String?
}

private struct CswapUsage: Decodable {
    let fiveHour: CswapUsageWindow
    let sevenDay: CswapUsageWindow
    let scoped: [CswapScopedUsageWindow]?
}

private struct CswapUsageWindow: Decodable {
    let pct: Double
    let resetsAt: String
}

private struct CswapScopedUsageWindow: Decodable {
    let name: String
    let pct: Double
    let resetsAt: String
}

extension CswapScopedUsageWindow {
    fileprivate var asWindow: CswapUsageWindow {
        CswapUsageWindow(pct: pct, resetsAt: resetsAt)
    }
}
