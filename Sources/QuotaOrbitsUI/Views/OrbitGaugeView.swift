import QuotaOrbitsCore
import SwiftUI

public enum OrbitGaugeDataState: Equatable, Sendable {
    case loading
    case available
    case unavailable
}

@_spi(Testing)
public enum OrbitGaugeAccessibility {
    public static func label(hasInner: Bool) -> String {
        hasInner
            ? "Остаток лимита: внутреннее кольцо 5 часов, внешнее кольцо 7 дней"
            : "Остаток лимита: кольцо 7 дней"
    }

    public static func value(
        inner: Double?,
        outer: Double?,
        hasInner: Bool? = nil,
        dataState: OrbitGaugeDataState? = nil
    ) -> String {
        let includesInner = hasInner ?? (inner != nil)
        let resolvedState = dataState ?? inferredState(inner: inner, outer: outer)
        if resolvedState == .loading {
            let loading = "данные загружаются"
            guard includesInner else { return "7 дней — \(loading)" }
            return "5 часов — \(loading); 7 дней — \(loading)"
        }
        if resolvedState == .unavailable {
            guard includesInner else { return "7 дней — нет данных" }
            return "5 часов — нет данных; 7 дней — нет данных"
        }
        let weekly = outer.map { "\(QuotaCopy.percent($0)) осталось" } ?? "нет данных"
        guard includesInner else { return "7 дней — \(weekly)" }
        let fiveHour = inner.map { "\(QuotaCopy.percent($0)) осталось" } ?? "нет данных"
        return "5 часов — \(fiveHour); 7 дней — \(weekly)"
    }

    private static func inferredState(
        inner: Double?,
        outer: Double?
    ) -> OrbitGaugeDataState {
        inner == nil && outer == nil ? .unavailable : .available
    }
}

public struct OrbitGaugeView: View {
    private let innerRemainingPercent: Double?
    private let weeklyRemainingPercent: Double?
    private let showsInnerRing: Bool
    private let dataState: OrbitGaugeDataState

    public init(
        weeklyRemainingPercent: Double?,
        dataState: OrbitGaugeDataState? = nil
    ) {
        innerRemainingPercent = nil
        self.weeklyRemainingPercent = weeklyRemainingPercent
        showsInnerRing = false
        self.dataState = dataState
            ?? (weeklyRemainingPercent == nil ? .unavailable : .available)
    }

    public init(
        fiveHourRemainingPercent: Double?,
        weeklyRemainingPercent: Double?,
        dataState: OrbitGaugeDataState? = nil
    ) {
        innerRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        showsInnerRing = true
        self.dataState = dataState
            ?? (fiveHourRemainingPercent == nil && weeklyRemainingPercent == nil
                ? .unavailable
                : .available)
    }

    public var body: some View {
        ZStack {
            orbit(percent: weeklyRemainingPercent, lineWidth: 7)

            if showsInnerRing {
                orbit(percent: innerRemainingPercent, lineWidth: 5)
                    .padding(14)
            }

            values
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OrbitGaugeAccessibility.label(hasInner: showsInnerRing))
        .accessibilityValue(
            OrbitGaugeAccessibility.value(
                inner: innerRemainingPercent,
                outer: weeklyRemainingPercent,
                hasInner: showsInnerRing,
                dataState: dataState
            )
        )
    }

    private func orbit(percent: Double?, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: normalized(percent) / 100)
                .stroke(
                    QuotaPalette.color(
                        for: QuotaLevel.classify(remainingPercent: percent)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder
    private var values: some View {
        if showsInnerRing {
            HStack(spacing: 3) {
                valueText(innerRemainingPercent)
                Text("/")
                    .foregroundStyle(Color.white.opacity(0.30))
                valueText(weeklyRemainingPercent)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        } else {
            Text(QuotaCopy.percent(weeklyRemainingPercent))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    QuotaPalette.color(
                        for: QuotaLevel.classify(
                            remainingPercent: weeklyRemainingPercent
                        )
                    )
                )
        }
    }

    private func valueText(_ percent: Double?) -> some View {
        Text(QuotaCopy.number(percent))
            .foregroundStyle(
                QuotaPalette.color(
                    for: QuotaLevel.classify(remainingPercent: percent)
                )
            )
    }

    private func normalized(_ percent: Double?) -> Double {
        min(max(percent ?? 0, 0), 100)
    }
}
