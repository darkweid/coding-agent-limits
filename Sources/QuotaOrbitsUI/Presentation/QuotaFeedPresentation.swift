import Foundation
import QuotaOrbitsCore

public enum ProviderSymbol: Equatable, Sendable {
    case claude
    case codex

    public var accessibilityLabel: String {
        switch self {
        case .claude: "Claude quota source"
        case .codex: "Codex quota source"
        }
    }
}

@_spi(Testing)
public struct QuotaLimitPresentation: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let displayPercent: Double
    public let displayMode: QuotaDisplayMode
    public let level: QuotaLevel
    public let resetsAt: Date
}

@_spi(Testing)
public struct QuotaBalancePresentation: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let amount: Decimal
    public let currencyCode: String?
}

@_spi(Testing)
public struct QuotaCardPresentation: Identifiable, Equatable, Sendable {
    public let id: String
    public let alias: String
    public let isActive: Bool
    public let symbol: ProviderSymbol
    public let limits: [QuotaLimitPresentation]
    public let balances: [QuotaBalancePresentation]
    public let status: PresentationStatus
}

@_spi(Testing)
public struct QuotaFeedPresentation: Equatable, Sendable {
    public let cards: [QuotaCardPresentation]
    public let lastSuccessfulRefreshAt: Date?

    public init(snapshot: QuotaFeedSnapshot, displayMode: QuotaDisplayMode) {
        var projected: [QuotaCardPresentation] = []
        var successDates: [Date] = []

        for entry in snapshot.entries {
            let sourceStatus: PresentationStatus
            let quota: ProviderQuota?
            switch entry.snapshot {
            case .loading:
                sourceStatus = .loading
                quota = nil
            case let .available(value, updatedAt):
                sourceStatus = .fresh
                quota = value
                successDates.append(updatedAt)
            case let .stale(value, lastSuccessAt, _):
                sourceStatus = .stale(lastSuccessAt: lastSuccessAt)
                quota = value
                successDates.append(lastSuccessAt)
            case .unavailable:
                sourceStatus = .unavailable
                quota = nil
            }

            let symbol = Self.symbol(
                providerID: quota?.providerID,
                sourceID: entry.sourceID
            )
            guard let quota, !quota.accounts.isEmpty else {
                let slot = projected.count + 1
                projected.append(
                    QuotaCardPresentation(
                        id: "card-\(slot)",
                        alias: Self.slotLabel(slot),
                        isActive: false,
                        symbol: symbol,
                        limits: [],
                        balances: [],
                        status: sourceStatus
                    )
                )
                continue
            }

            for (accountIndex, account) in quota.accounts.enumerated() {
                let slot = projected.count + 1
                let status = Self.status(for: account.state, sourceStatus: sourceStatus)
                let limits = account.limits.enumerated().map { limitIndex, limit in
                    QuotaLimitPresentation(
                        id: "card-\(slot)-limit-\(limitIndex + 1)",
                        label: Self.safeLimitLabel(limit.label, slot: limitIndex + 1),
                        displayPercent: displayMode == .used
                            ? limit.usedPercent : limit.remainingPercent,
                        displayMode: displayMode,
                        level: limit.level,
                        resetsAt: limit.resetsAt
                    )
                }
                let balances =
                    accountIndex == 0
                    ? quota.balances.enumerated().map { index, balance in
                        QuotaBalancePresentation(
                            id: "card-\(slot)-balance-\(index + 1)",
                            label: Self.safeLimitLabel(balance.label, slot: index + 1),
                            amount: balance.amount,
                            currencyCode: balance.currencyCode
                        )
                    } : []
                projected.append(
                    QuotaCardPresentation(
                        id: "card-\(slot)",
                        alias: Self.safeAlias(account.alias, slot: slot),
                        isActive: account.isActive,
                        symbol: symbol,
                        limits: limits,
                        balances: balances,
                        status: status
                    )
                )
            }
        }

        cards = projected
        lastSuccessfulRefreshAt = successDates.max()
    }

    private static func status(
        for accountState: AccountDataState,
        sourceStatus: PresentationStatus
    ) -> PresentationStatus {
        switch accountState {
        case .fresh:
            return sourceStatus
        case let .stale(lastSuccessAt):
            return .stale(lastSuccessAt: lastSuccessAt)
        case .unavailable:
            return .unavailable
        }
    }

    private static func symbol(
        providerID: ProviderID?,
        sourceID: QuotaSourceID
    ) -> ProviderSymbol {
        if providerID == .codex || sourceID == .codexAppServer { return .codex }
        return .claude
    }

    private static func safeAlias(_ alias: String, slot: Int) -> String {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = value.lowercased()
        let forbidden = ["claude", "codex", "anthropic", "openai"]
        guard
            !value.isEmpty,
            value.count <= 40,
            !value.contains("@"),
            !forbidden.contains(where: lowered.contains),
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else {
            return slotLabel(slot)
        }
        return value
    }

    private static func safeLimitLabel(_ label: String, slot: Int) -> String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !value.isEmpty,
            value.count <= 40,
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else {
            return "Limit \(String(format: "%02d", slot))"
        }
        return value
    }

    private static func slotLabel(_ slot: Int) -> String {
        String(format: "%02d", slot)
    }
}
