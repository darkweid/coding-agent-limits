import QuotaOrbitsCore
import SwiftUI

struct ClaudeAccountCard: View {
    let account: AccountCardPresentation
    let displayMode: QuotaDisplayMode
    let visualStyle: QuotaVisualStyle
    var fixedNow: Date?

    var body: some View {
        Group {
            if let fixedNow {
                content(now: fixedNow)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(now: context.date)
                }
            }
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ClaudeMark()
                    .frame(
                        width: ProviderMarkMetrics.canvasSize,
                        height: ProviderMarkMetrics.canvasSize
                    )
                    .foregroundStyle(Color(red: 0.85, green: 0.43, blue: 0.29))
                    .accessibilityHidden(true)
                Text(account.alias)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                ProviderActiveIndicator(provider: .claude, isActive: account.isActive)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                ProviderHeaderCopy.claudeAccessibilityLabel(
                    alias: account.alias,
                    isActive: account.isActive
                )
            )

            Group {
                if visualStyle == .orbits {
                    HStack(spacing: 4) {
                        quotaGauge(window: "5 hours", quotaWindow: account.fiveHour, now: now)
                        quotaGauge(window: "7 days", quotaWindow: account.weekly, now: now)
                        ForEach(Array(account.scoped.enumerated()), id: \.offset) { _, scoped in
                            quotaGauge(window: scoped.label, quotaWindow: scoped.window, now: now)
                        }
                    }
                } else {
                    quotaGauge(window: "5 hours", quotaWindow: account.fiveHour, now: now)
                    quotaGauge(window: "7 days", quotaWindow: account.weekly, now: now)
                    ForEach(Array(account.scoped.enumerated()), id: \.offset) { _, scoped in
                        quotaGauge(window: scoped.label, quotaWindow: scoped.window, now: now)
                    }
                }
            }

            statusLine(now: now)
        }
        .padding(9)
        .frame(
            height: DashboardLayout.claudeAccountHeight(
                scopedCount: account.scoped.count,
                visualStyle: visualStyle
            ),
            alignment: .top
        )
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    private func quotaGauge(
        window: String,
        quotaWindow: QuotaWindow?,
        now: Date
    ) -> some View {
        QuotaGaugeView(
            window: window,
            countdown: account.status.resetCountdown(window: quotaWindow, now: now),
            usedPercent: quotaWindow?.usedPercent,
            dataState: account.status.barDataState,
            displayMode: displayMode,
            visualStyle: visualStyle
        )
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let text = account.status.text(now: now) {
            HStack(spacing: 4) {
                if account.status.isStale {
                    Circle()
                        .fill(QuotaPalette.color(for: .warning))
                        .frame(width: 5, height: 5)
                }
                Text(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.46))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 10)
        }
    }
}
