import Foundation

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

public struct QuotaWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(usedPercent: Double, resetsAt: Date) {
        let normalizedUsed = min(max(usedPercent, 0), 100)
        self.usedPercent = normalizedUsed
        self.remainingPercent = 100 - normalizedUsed
        self.resetsAt = resetsAt
    }
}

public struct ClaudeAccountQuota: Equatable, Sendable {
    public let id: String
    public let alias: String
    public let isActive: Bool
    public let fiveHour: QuotaWindow
    public let weekly: QuotaWindow

    public init(
        id: String,
        alias: String,
        isActive: Bool,
        fiveHour: QuotaWindow,
        weekly: QuotaWindow
    ) {
        self.id = id
        self.alias = alias
        self.isActive = isActive
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

public struct CodexQuota: Equatable, Sendable {
    public let weekly: QuotaWindow
    public let creditsBalance: Decimal?

    public init(weekly: QuotaWindow, creditsBalance: Decimal?) {
        self.weekly = weekly
        self.creditsBalance = creditsBalance
    }
}

public enum SourceSnapshot<Value: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case available(Value, updatedAt: Date)
    case stale(Value, lastSuccessAt: Date, message: String)
    case unavailable(message: String)
}

public struct QuotaSnapshot: Equatable, Sendable {
    public var claude: SourceSnapshot<[ClaudeAccountQuota]>
    public var codex: SourceSnapshot<CodexQuota>
    public var lastCycleStartedAt: Date?

    public init(
        claude: SourceSnapshot<[ClaudeAccountQuota]> = .loading,
        codex: SourceSnapshot<CodexQuota> = .loading,
        lastCycleStartedAt: Date? = nil
    ) {
        self.claude = claude
        self.codex = codex
        self.lastCycleStartedAt = lastCycleStartedAt
    }

    public static let initial = QuotaSnapshot()
}

public protocol ClaudeQuotaFetching: Sendable {
    func fetch() async throws -> [ClaudeAccountQuota]
}

public protocol CodexQuotaFetching: Sendable {
    func fetch() async throws -> CodexQuota
}
