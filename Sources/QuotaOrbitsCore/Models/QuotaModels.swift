import Foundation

public struct ProviderID: Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let claude = Self(rawValue: "claude")
    public static let codex = Self(rawValue: "codex")
}

public struct QuotaSourceID: Hashable, RawRepresentable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let cswap = Self(rawValue: "cswap")
    public static let claudeCode = Self(rawValue: "claude-code")
    public static let codexAppServer = Self(rawValue: "codex-app-server")
}

public enum QuotaLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unavailable

    public static func classify(usedPercent: Double?) -> Self {
        guard let usedPercent else { return .unavailable }
        if usedPercent <= 70 { return .healthy }
        if usedPercent <= 85 { return .warning }
        return .critical
    }
}

public struct QuotaLimit: Equatable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date

    public var remainingPercent: Double { 100 - usedPercent }
    public var level: QuotaLevel { .classify(usedPercent: usedPercent) }

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date) {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent.isFinite ? min(max(usedPercent, 0), 100) : 0
        self.resetsAt = resetsAt
    }
}

public struct QuotaBalance: Equatable, Sendable {
    public let label: String
    public let amount: Decimal
    public let currencyCode: String?

    public init(label: String, amount: Decimal, currencyCode: String?) {
        self.label = label
        self.amount = amount
        self.currencyCode = currencyCode
    }
}

public enum AccountDataState: Equatable, Sendable {
    case fresh
    case stale(lastSuccessAt: Date)
    case unavailable
}

public struct QuotaAccount: Equatable, Sendable {
    public let id: String
    public let alias: String
    public let isActive: Bool
    public let state: AccountDataState
    public let limits: [QuotaLimit]

    public init(
        id: String,
        alias: String,
        isActive: Bool,
        state: AccountDataState,
        limits: [QuotaLimit]
    ) {
        self.id = id
        self.alias = alias
        self.isActive = isActive
        self.state = state
        self.limits = limits
    }
}

public struct ProviderQuota: Equatable, Sendable {
    public let providerID: ProviderID
    public let accounts: [QuotaAccount]
    public let balances: [QuotaBalance]

    public init(
        providerID: ProviderID,
        accounts: [QuotaAccount],
        balances: [QuotaBalance] = []
    ) {
        self.providerID = providerID
        self.accounts = accounts
        self.balances = balances
    }
}

public protocol QuotaSource: Sendable {
    var sourceID: QuotaSourceID { get }
    var providerID: ProviderID { get }
    func fetch() async throws -> ProviderQuota
}

public enum SourceSnapshot<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case available(Value, updatedAt: Date)
    case stale(Value, lastSuccessAt: Date, message: String)
    case unavailable(message: String)
}

public struct QuotaFeedSnapshot: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let sourceID: QuotaSourceID
        public var snapshot: SourceSnapshot<ProviderQuota>

        public init(
            sourceID: QuotaSourceID,
            snapshot: SourceSnapshot<ProviderQuota>
        ) {
            self.sourceID = sourceID
            self.snapshot = snapshot
        }
    }

    public var entries: [Entry]
    public var lastCycleStartedAt: Date?

    public init(entries: [Entry], lastCycleStartedAt: Date? = nil) {
        self.entries = entries
        self.lastCycleStartedAt = lastCycleStartedAt
    }
}
