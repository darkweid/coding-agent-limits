import SwiftUI
import QuotaOrbitsCore

public enum QuotaColorToken: Equatable, Sendable {
    case healthy
    case low
    case critical
    case unavailable
}

public enum QuotaPalette {
    public static func token(for level: QuotaLevel) -> QuotaColorToken {
        switch level {
        case .healthy: .healthy
        case .low: .low
        case .critical: .critical
        case .unavailable: .unavailable
        }
    }

    public static func color(for level: QuotaLevel) -> Color {
        switch token(for: level) {
        case .healthy: Color(red: 0.47, green: 0.71, blue: 0.59)
        case .low: Color(red: 0.85, green: 0.60, blue: 0.33)
        case .critical: Color(red: 0.84, green: 0.43, blue: 0.40)
        case .unavailable: Color(red: 0.30, green: 0.31, blue: 0.33)
        }
    }
}
