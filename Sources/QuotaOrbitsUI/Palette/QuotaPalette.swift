import SwiftUI
import QuotaOrbitsCore

public enum QuotaColorToken: Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unavailable
}

@_spi(Testing)
public struct QuotaColorComponents: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum QuotaPalette {
    public static func token(for level: QuotaLevel) -> QuotaColorToken {
        switch level {
        case .healthy: .healthy
        case .warning: .warning
        case .critical: .critical
        case .unavailable: .unavailable
        }
    }

    @_spi(Testing)
    public static func components(
        for level: QuotaLevel
    ) -> QuotaColorComponents {
        switch token(for: level) {
        case .healthy: QuotaColorComponents(red: 0.47, green: 0.71, blue: 0.59)
        case .warning: QuotaColorComponents(red: 0.91, green: 0.72, blue: 0.28)
        case .critical: QuotaColorComponents(red: 0.84, green: 0.43, blue: 0.40)
        case .unavailable: QuotaColorComponents(red: 0.30, green: 0.31, blue: 0.33)
        }
    }

    public static func color(for level: QuotaLevel) -> Color {
        let components = components(for: level)
        return Color(
            red: components.red,
            green: components.green,
            blue: components.blue
        )
    }
}
