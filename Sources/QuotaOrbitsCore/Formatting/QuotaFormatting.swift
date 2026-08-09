import Foundation

public enum ResetCountdownFormatter {
    public static func string(until reset: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(reset.timeIntervalSince(now)) / 60)
        guard totalMinutes > 0 else { return "resets now" }

        let totalHours = totalMinutes / 60
        if totalHours >= 24 {
            return "resets in \(totalHours / 24)d \(totalHours % 24)h"
        }
        if totalHours > 0 {
            return "resets in \(totalHours)h \(totalMinutes % 60)m"
        }
        return "resets in \(totalMinutes)m"
    }
}
