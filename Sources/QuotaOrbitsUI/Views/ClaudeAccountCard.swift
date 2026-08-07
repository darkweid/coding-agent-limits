import SwiftUI

struct ClaudeAccountCard: View {
    let account: AccountCardPresentation
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
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text(account.alias)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                if account.isActive {
                    Circle()
                        .fill(QuotaPalette.color(for: .healthy))
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Активен")
                }
            }

            OrbitGaugeView(
                fiveHourRemainingPercent: account.fiveHour?.remainingPercent,
                weeklyRemainingPercent: account.weekly?.remainingPercent
            )
            .frame(width: 91, height: 91)

            VStack(alignment: .leading, spacing: 3) {
                resetLine(QuotaCopy.reset(prefix: "5ч", window: account.fiveHour, now: now))
                resetLine(QuotaCopy.reset(prefix: "7д", window: account.weekly, now: now))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusLine(now: now)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }

    private func resetLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.64))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        if let text = account.status.text(now: now) {
            HStack(spacing: 4) {
                if account.status.isStale {
                    Circle()
                        .fill(QuotaPalette.color(for: .low))
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
            Color.clear.frame(height: 11)
        }
    }
}
