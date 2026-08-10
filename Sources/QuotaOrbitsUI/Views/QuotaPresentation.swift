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

    public static func resetCountdown(resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "no data" }
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
public enum PresentationStatus: Equatable, Sendable {
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

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}
