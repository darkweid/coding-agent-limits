import QuotaOrbitsCore
import SwiftUI

public enum QuotaBarDataState: Equatable, Sendable {
    case loading
    case available
    case unavailable
}

@_spi(Testing)
public enum QuotaBarMetrics {
    public static func normalized(_ percent: Double?) -> Double {
        min(max(percent ?? 0, 0), 100)
    }
}

@_spi(Testing)
public enum QuotaBarAccessibility {
    public static func value(
        window: String,
        remaining: Double?,
        dataState: QuotaBarDataState
    ) -> String {
        switch dataState {
        case .loading:
            return "\(window), loading"
        case .unavailable:
            return "\(window), no data"
        case .available:
            guard let remaining else { return "\(window), no data" }
            return "\(window), \(QuotaCopy.percent(remaining)) remaining"
        }
    }
}

struct QuotaBarView: View {
    let window: String
    let countdown: String
    let remainingPercent: Double?
    let dataState: QuotaBarDataState

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Text(window)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white.opacity(0.74))
                Text("· \(countdown)")
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 4)
                Text(QuotaCopy.percent(remainingPercent))
                    .fontWeight(.semibold)
                    .foregroundStyle(levelColor)
            }
            .font(.system(size: 10, design: .rounded))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(levelColor)
                        .frame(
                            width: geometry.size.width
                                * QuotaBarMetrics.normalized(remainingPercent)
                                / 100
                        )
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota remaining")
        .accessibilityValue(
            QuotaBarAccessibility.value(
                window: window,
                remaining: remainingPercent,
                dataState: dataState
            )
        )
    }

    private var levelColor: Color {
        QuotaPalette.color(
            for: QuotaLevel.classify(remainingPercent: remainingPercent)
        )
    }
}
