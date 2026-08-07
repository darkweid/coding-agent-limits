import Foundation

public enum ResetCountdownFormatter {
    public static func string(until reset: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(reset.timeIntervalSince(now)) / 60)
        guard totalMinutes > 0 else { return "сброс сейчас" }

        let totalHours = totalMinutes / 60
        if totalHours >= 24 {
            return "сброс через \(totalHours / 24)д \(totalHours % 24)ч"
        }
        if totalHours > 0 {
            return "сброс через \(totalHours)ч \(totalMinutes % 60)м"
        }
        return "сброс через \(totalMinutes)м"
    }
}
