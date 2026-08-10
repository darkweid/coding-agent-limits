import QuotaOrbitsCore
import SwiftUI

@MainActor
public final class DashboardActions: ObservableObject {
    @Published public var isPinned: Bool
    public let refreshNow: () -> Void
    public let togglePinned: () -> Void
    public let openSettings: () -> Void
    public let quit: () -> Void

    public init(
        isPinned: Bool,
        refreshNow: @escaping () -> Void,
        togglePinned: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.isPinned = isPinned
        self.refreshNow = refreshNow
        self.togglePinned = togglePinned
        self.openSettings = openSettings
        self.quit = quit
    }
}

public struct DashboardView: View {
    @ObservedObject private var coordinator: QuotaFeedRefreshCoordinator
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var actions: DashboardActions

    @MainActor
    public init(
        coordinator: QuotaFeedRefreshCoordinator,
        preferences: AppPreferences,
        actions: DashboardActions
    ) {
        self.coordinator = coordinator
        self.preferences = preferences
        self.actions = actions
    }

    public var body: some View {
        DashboardContentView(
            presentation: QuotaFeedPresentation(
                snapshot: coordinator.snapshot,
                displayMode: preferences.displayMode
            ),
            visualStyle: preferences.visualStyle,
            actions: actions
        )
    }
}

struct DashboardContentView: View {
    let presentation: QuotaFeedPresentation
    let visualStyle: QuotaVisualStyle
    @ObservedObject var actions: DashboardActions
    var fixedNow: Date?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                if let date = presentation.lastSuccessfulRefreshAt {
                    Text(QuotaCopy.lastRefresh(date))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
            .frame(height: 12)

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(presentation.cards) { card in
                        QuotaAccountCard(
                            card: card,
                            visualStyle: visualStyle,
                            fixedNow: fixedNow
                        )
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(12)
        .frame(width: 350, height: 350)
        .background(panelBackground)
        .contextMenu {
            let labels = DashboardCopy.contextActions(isPinned: actions.isPinned)
            Button(labels[0], action: actions.refreshNow)
            Button(labels[1], action: actions.togglePinned)
            Divider()
            Button(labels[2], action: actions.openSettings)
            Button(labels[3], action: actions.quit)
        }
        .preferredColorScheme(.dark)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.055, green: 0.057, blue: 0.062).opacity(0.90))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.75)
        }
    }
}
