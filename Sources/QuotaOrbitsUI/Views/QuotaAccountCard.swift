import SwiftUI

struct QuotaAccountCard: View {
    let card: QuotaCardPresentation
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
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                ProviderSymbolView(symbol: card.symbol)
                Text(card.alias)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if card.isActive {
                    Circle()
                        .fill(QuotaPalette.color(for: .healthy))
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Active account")
                }
            }

            if !card.balances.isEmpty {
                HStack {
                    ForEach(card.balances) { balance in
                        Text("\(balance.label) \(QuotaCopy.credits(balance.amount))")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                    Spacer()
                }
            }

            if visualStyle == .bars {
                VStack(spacing: 7) {
                    ForEach(card.limits) { limit in
                        QuotaLimitBarView(limit: limit, status: card.status, now: now)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(card.limits) { limit in
                        QuotaOrbitView(limit: limit, status: card.status, now: now)
                    }
                }
            }

            if let status = card.status.text(now: now) {
                Text(status)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
    }
}
