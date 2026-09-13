import Foundation
import QuotaOrbitsCore

@_spi(Testing)
public enum QuotaCopy {
    public static func number(_ usedPercent: Double?) -> String {
        guard let usedPercent else { return "—" }
        return String(Int(usedPercent.rounded()))
    }

    public static func percent(_ usedPercent: Double?) -> String {
        guard usedPercent != nil else { return "—" }
        return "\(number(usedPercent))%"
    }

    public static func resetCountdown(window: QuotaWindow?, now: Date) -> String {
        guard let window else { return "no data" }
        guard let resetsAt = window.resetsAt else { return "reset unavailable" }
        return ResetCountdownFormatter.string(until: resetsAt, now: now)
    }

    public static func stale(lastSuccessAt: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(lastSuccessAt)) / 60)
        return "updated \(minutes) min ago"
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "updated \(formatter.string(from: date))"
    }
}

@_spi(Testing)
public enum DashboardCopy {
    public static func contextActions(isPinned: Bool) -> [String] {
        [
            "Refresh Now",
            isPinned ? "Move" : "Pin",
            "Settings…",
            "Quit",
        ]
    }
}

@_spi(Testing)
public enum ProviderHeaderCopy {
    public static let claudeMark = "✳"
    public static let codexTitle = "codex"
    public static let openAIAccessibilityLabel = "OpenAI"

    public static func claudeAccessibilityLabel(alias: String, isActive: Bool) -> String {
        let identity = "Claude \(alias)"
        return isActive ? "\(identity), active account" : identity
    }
}

@_spi(Testing)
public enum PresentationStatus: Equatable {
    case loading
    case fresh
    case stale(lastSuccessAt: Date)
    case unavailable

    public func text(now: Date) -> String? {
        switch self {
        case .loading, .fresh:
            nil
        case let .stale(lastSuccessAt):
            QuotaCopy.stale(lastSuccessAt: lastSuccessAt, now: now)
        case .unavailable:
            "no data"
        }
    }

    public func resetCountdown(
        window: QuotaWindow?,
        now: Date
    ) -> String {
        if self == .loading, window == nil {
            return "—"
        }
        return QuotaCopy.resetCountdown(window: window, now: now)
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    public var barDataState: QuotaBarDataState {
        switch self {
        case .loading: .loading
        case .fresh, .stale: .available
        case .unavailable: .unavailable
        }
    }
}

@_spi(Testing)
public struct AccountCardPresentation: Identifiable, Equatable {
    public let id: String
    public let alias: String
    public let isActive: Bool
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let scoped: [ClaudeScopedQuota]
    public let status: PresentationStatus
}

@_spi(Testing)
public struct CodexCardPresentation: Equatable {
    public let fiveHour: QuotaWindow?
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
            Self.successDate(from: snapshot.codex),
        ]
        .compactMap { $0 }
        .max()
    }

    private static func accounts(
        from source: SourceSnapshot<[ClaudeAccountQuota]>
    ) -> [AccountCardPresentation] {
        switch source {
        case let .available(values, _):
            return accountCards(values: values)
        case let .stale(values, lastSuccessAt, _):
            return accountCards(values: values, sourceStaleAt: lastSuccessAt)
        case .loading:
            return placeholderAccounts(status: .loading)
        case .unavailable:
            return placeholderAccounts(status: .unavailable)
        }
    }

    private static func accountCards(
        values: [ClaudeAccountQuota],
        sourceStaleAt: Date? = nil
    ) -> [AccountCardPresentation] {
        var result = values.prefix(2).enumerated().map { index, account in
            AccountCardPresentation(
                id: "slot-\(index + 1)",
                alias: safeAlias(account.alias, slot: index),
                isActive: account.isActive,
                fiveHour: account.fiveHour,
                weekly: account.weekly,
                scoped: safeScoped(account.scoped),
                status: accountStatus(account.state, sourceStaleAt: sourceStaleAt)
            )
        }
        while result.count < 2 {
            let slot = result.count
            result.append(placeholderAccount(slot: slot))
        }
        return result
    }

    private static func accountStatus(
        _ state: ClaudeAccountQuotaState,
        sourceStaleAt: Date?
    ) -> PresentationStatus {
        switch state {
        case .unavailable:
            return .unavailable
        case .fresh:
            guard let sourceStaleAt else { return .fresh }
            return .stale(lastSuccessAt: sourceStaleAt)
        case let .stale(accountStaleAt):
            guard let sourceStaleAt else {
                return .stale(lastSuccessAt: accountStaleAt)
            }
            return .stale(lastSuccessAt: min(accountStaleAt, sourceStaleAt))
        }
    }

    private static func placeholderAccounts(
        status: PresentationStatus
    ) -> [AccountCardPresentation] {
        [
            placeholderAccount(slot: 0, status: status),
            placeholderAccount(slot: 1, status: status),
        ]
    }

    private static func placeholderAccount(
        slot: Int,
        status: PresentationStatus = .unavailable
    ) -> AccountCardPresentation {
        AccountCardPresentation(
            id: "slot-\(slot + 1)",
            alias: String(format: "%02d", slot + 1),
            isActive: false,
            fiveHour: nil,
            weekly: nil,
            scoped: [],
            status: status
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

    private static func safeScoped(
        _ values: [ClaudeScopedQuota]
    ) -> [ClaudeScopedQuota] {
        let safeValues = values.compactMap { value -> ClaudeScopedQuota? in
            let label = value.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowered = label.lowercased()
            guard !label.isEmpty,
                label.count <= 40,
                !label.contains("@"),
                !["claude", "codex"].contains(where: lowered.contains),
                label.unicodeScalars.allSatisfy({
                    !CharacterSet.controlCharacters.contains($0)
                })
            else { return nil }
            return ClaudeScopedQuota(label: label, window: value.window)
        }
        return Array(safeValues.prefix(1))
    }

    private static func codex(
        from source: SourceSnapshot<CodexQuota>
    ) -> CodexCardPresentation {
        switch source {
        case let .available(value, _):
            CodexCardPresentation(
                fiveHour: value.fiveHour,
                weekly: value.weekly,
                creditsBalance: value.creditsBalance,
                status: .fresh
            )
        case let .stale(value, lastSuccessAt, _):
            CodexCardPresentation(
                fiveHour: value.fiveHour,
                weekly: value.weekly,
                creditsBalance: value.creditsBalance,
                status: .stale(lastSuccessAt: lastSuccessAt)
            )
        case .loading:
            CodexCardPresentation(
                fiveHour: nil,
                weekly: nil,
                creditsBalance: nil,
                status: .loading
            )
        case .unavailable:
            CodexCardPresentation(
                fiveHour: nil,
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
