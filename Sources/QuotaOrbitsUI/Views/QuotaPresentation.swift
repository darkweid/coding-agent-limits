import Foundation
import QuotaOrbitsCore

@_spi(Testing)
public enum QuotaCopy {
    public static func number(_ remainingPercent: Double?) -> String {
        guard let remainingPercent else { return "—" }
        return String(Int(remainingPercent.rounded()))
    }

    public static func percent(_ remainingPercent: Double?) -> String {
        guard remainingPercent != nil else { return "—" }
        return "\(number(remainingPercent))%"
    }

    public static func reset(prefix: String, window: QuotaWindow?, now: Date) -> String {
        guard let window else { return "\(prefix) · нет данных" }
        return "\(prefix) · \(ResetCountdownFormatter.string(until: window.resetsAt, now: now))"
    }

    public static func stale(lastSuccessAt: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(lastSuccessAt)) / 60)
        return "обновлено \(minutes) мин назад"
    }

    public static func credits(_ balance: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: balance as NSDecimalNumber) ?? "—"
    }

    public static func lastRefresh(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU_POSIX")
        formatter.dateFormat = "HH:mm"
        return "обновлено \(formatter.string(from: date))"
    }
}

@_spi(Testing)
public enum DashboardCopy {
    public static func contextActions(isPinned: Bool) -> [String] {
        [
            "Обновить сейчас",
            isPinned ? "Переместить" : "Закрепить",
            "Настройки…",
            "Выйти"
        ]
    }
}

@_spi(Testing)
public enum PresentationStatus: Equatable {
    case fresh
    case stale(lastSuccessAt: Date)
    case unavailable

    public func text(now: Date) -> String? {
        switch self {
        case .fresh:
            nil
        case let .stale(lastSuccessAt):
            QuotaCopy.stale(lastSuccessAt: lastSuccessAt, now: now)
        case .unavailable:
            "нет данных"
        }
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

@_spi(Testing)
public struct AccountCardPresentation: Identifiable, Equatable {
    public let id: String
    public let alias: String
    public let isActive: Bool
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let status: PresentationStatus
}

@_spi(Testing)
public struct CodexCardPresentation: Equatable {
    public let symbol = "◇"
    public let weekly: QuotaWindow?
    public let creditsBalance: Decimal?
    public let status: PresentationStatus
}

@_spi(Testing)
public struct DashboardPresentation: Equatable {
    public let accounts: [AccountCardPresentation]
    public let codex: CodexCardPresentation
    public let lastSuccessfulRefreshAt: Date?

    public init(snapshot: QuotaSnapshot) {
        accounts = Self.accounts(from: snapshot.claude)
        codex = Self.codex(from: snapshot.codex)
        lastSuccessfulRefreshAt = [
            Self.successDate(from: snapshot.claude),
            Self.successDate(from: snapshot.codex)
        ]
        .compactMap { $0 }
        .max()
    }

    private static func accounts(
        from source: SourceSnapshot<[ClaudeAccountQuota]>
    ) -> [AccountCardPresentation] {
        switch source {
        case let .available(values, _):
            return accountCards(values: values, status: .fresh)
        case let .stale(values, lastSuccessAt, _):
            return accountCards(values: values, status: .stale(lastSuccessAt: lastSuccessAt))
        case .loading, .unavailable:
            return placeholderAccounts()
        }
    }

    private static func accountCards(
        values: [ClaudeAccountQuota],
        status: PresentationStatus
    ) -> [AccountCardPresentation] {
        var result = values.prefix(2).enumerated().map { index, account in
            AccountCardPresentation(
                id: "slot-\(index + 1)",
                alias: safeAlias(account.alias, slot: index),
                isActive: account.isActive,
                fiveHour: account.fiveHour,
                weekly: account.weekly,
                status: status
            )
        }
        while result.count < 2 {
            let slot = result.count
            result.append(placeholderAccount(slot: slot))
        }
        return result
    }

    private static func placeholderAccounts() -> [AccountCardPresentation] {
        [placeholderAccount(slot: 0), placeholderAccount(slot: 1)]
    }

    private static func placeholderAccount(slot: Int) -> AccountCardPresentation {
        AccountCardPresentation(
            id: "slot-\(slot + 1)",
            alias: String(format: "%02d", slot + 1),
            isActive: false,
            fiveHour: nil,
            weekly: nil,
            status: .unavailable
        )
    }

    private static func safeAlias(_ alias: String, slot: Int) -> String {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let forbiddenFragments = ["claude", "codex"]
        guard !trimmed.isEmpty,
              !trimmed.contains("@"),
              !forbiddenFragments.contains(where: lowered.contains)
        else {
            return String(format: "%02d", slot + 1)
        }
        return trimmed
    }

    private static func codex(
        from source: SourceSnapshot<CodexQuota>
    ) -> CodexCardPresentation {
        switch source {
        case let .available(value, _):
            CodexCardPresentation(
                weekly: value.weekly,
                creditsBalance: value.creditsBalance,
                status: .fresh
            )
        case let .stale(value, lastSuccessAt, _):
            CodexCardPresentation(
                weekly: value.weekly,
                creditsBalance: value.creditsBalance,
                status: .stale(lastSuccessAt: lastSuccessAt)
            )
        case .loading, .unavailable:
            CodexCardPresentation(
                weekly: nil,
                creditsBalance: nil,
                status: .unavailable
            )
        }
    }

    private static func successDate<Value>(
        from source: SourceSnapshot<Value>
    ) -> Date? where Value: Equatable & Sendable {
        switch source {
        case let .available(_, updatedAt): updatedAt
        case let .stale(_, lastSuccessAt, _): lastSuccessAt
        case .loading, .unavailable: nil
        }
    }
}
