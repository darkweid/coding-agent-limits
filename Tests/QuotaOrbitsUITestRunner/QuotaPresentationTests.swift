import Foundation
import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum QuotaPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static let cases: [TestCase] = [
        TestCase(name: "QuotaPresentationTests.testQuotaCopyFormatsValuesForDisplay") {
            guard let credits = Decimal(string: "411.5127706250") else {
                throw AssertionFailure(message: "Could not create the credits fixture")
            }
            try TestSupport.assertEqual(QuotaCopy.percent(28.4), "28%")
            try TestSupport.assertEqual(QuotaCopy.percent(nil), "—")
            try TestSupport.assertEqual(
                QuotaCopy.resetCountdown(window: window(remaining: 28, minutes: 205), now: now),
                "resets in 3h 25m"
            )
            try TestSupport.assertEqual(
                QuotaCopy.resetCountdown(
                    window: QuotaWindow(usedPercent: 100, resetsAt: nil),
                    now: now
                ),
                "reset unavailable"
            )
            try TestSupport.assertEqual(QuotaCopy.resetCountdown(window: nil, now: now), "no data")
            try TestSupport.assertEqual(
                QuotaCopy.stale(lastSuccessAt: now.addingTimeInterval(-125), now: now),
                "updated 2 min ago")
            try TestSupport.assertEqual(QuotaCopy.credits(credits), "411.51")
        },
        TestCase(name: "QuotaPresentationTests.testContextActionsUseNeutralApprovedCopy") {
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: true),
                ["Refresh Now", "Move", "Settings…", "Quit"]
            )
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: false),
                ["Refresh Now", "Pin", "Settings…", "Quit"]
            )
        },
        TestCase(name: "QuotaPresentationTests.testProviderHeadersUseBrandMarksAndStableNames") {
            try TestSupport.assertEqual(ProviderHeaderCopy.claudeMark, "✳")
            try TestSupport.assertEqual(ProviderHeaderCopy.codexTitle, "codex")
            try TestSupport.assertEqual(ProviderHeaderCopy.openAIAccessibilityLabel, "OpenAI")
            try TestSupport.assertEqual(
                ProviderHeaderCopy.claudeAccessibilityLabel(alias: "max", isActive: true),
                "Claude max, active account"
            )
            try TestSupport.assertEqual(
                ProviderHeaderCopy.claudeAccessibilityLabel(alias: "pro", isActive: false),
                "Claude pro"
            )
        },
        TestCase(
            name: "QuotaPresentationTests.testDashboardProjectionNeverRetainsIdentifiersOrErrors"
        ) {
            let accounts = [
                account(
                    id: "private@example.com", alias: "private@example.com", active: true,
                    inner: 100, outer: 81),
                account(
                    id: "second@example.com", alias: "Claude Code", active: false, inner: 28,
                    outer: 93),
            ]
            let snapshot = QuotaSnapshot(
                claude: .stale(
                    accounts, lastSuccessAt: now.addingTimeInterval(-120),
                    message: "token for private@example.com failed"),
                codex: .unavailable(message: "Codex transport includes technical details"),
                lastCycleStartedAt: now
            )

            let presentation = DashboardPresentation(snapshot: snapshot)

            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.accounts.map(\.id), ["slot-1", "slot-2"])
            try TestSupport.assertEqual(
                presentation.accounts[0].status.text(now: now), "updated 2 min ago")
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), "no data")
        },
        TestCase(
            name: "QuotaPresentationTests.testDashboardProjectionKeepsTwoAliasesAndLatestSuccess"
        ) {
            let accounts = [
                account(
                    id: "one",
                    alias: "max",
                    active: true,
                    inner: 100,
                    outer: 81,
                    scoped: [
                        ClaudeScopedQuota(
                            label: "Fable",
                            window: window(remaining: 21)
                        ),
                        ClaudeScopedQuota(
                            label: "Other",
                            window: window(remaining: 75)
                        ),
                        ClaudeScopedQuota(
                            label: "private@example.invalid",
                            window: window(remaining: 88)
                        ),
                    ]
                ),
                account(
                    id: "two", alias: "очень-длинное-нейтральное-имя", active: false, inner: 28,
                    outer: 93),
            ]
            let snapshot = QuotaSnapshot(
                claude: .available(accounts, updatedAt: now.addingTimeInterval(-60)),
                codex: .available(codex(remaining: 50), updatedAt: now),
                lastCycleStartedAt: now
            )

            let presentation = DashboardPresentation(snapshot: snapshot)

            try TestSupport.assertEqual(presentation.accounts.count, 2)
            try TestSupport.assertEqual(
                presentation.accounts.map(\.alias), ["max", "очень-длинное-нейтральное-имя"])
            try TestSupport.assertEqual(
                presentation.accounts.map(\.fiveHour?.remainingPercent), [100, 28])
            try TestSupport.assertEqual(
                presentation.accounts.map(\.weekly?.remainingPercent), [81, 93])
            try TestSupport.assertEqual(
                presentation.accounts[0].scoped.map(\.label), ["Fable"])
            try TestSupport.assertEqual(
                presentation.accounts[0].scoped.map(\.window.remainingPercent), [21])
            try TestSupport.assertEqual(presentation.accounts[1].scoped, [])
            try TestSupport.assertEqual(presentation.codex.fiveHour?.remainingPercent, 25)
            try TestSupport.assertEqual(presentation.codex.weekly?.remainingPercent, 50)
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, now)
        },
        TestCase(name: "QuotaPresentationTests.testUnavailableProjectionUsesNeutralPlaceholders") {
            let presentation = DashboardPresentation(
                snapshot: QuotaSnapshot(
                    claude: .unavailable(message: "private failure"),
                    codex: .unavailable(message: "private failure")
                )
            )

            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.accounts.map(\.fiveHour), [nil, nil])
            try TestSupport.assertEqual(presentation.accounts.map(\.weekly), [nil, nil])
            try TestSupport.assertEqual(
                presentation.accounts.map { $0.status.text(now: now) }, ["no data", "no data"])
            try TestSupport.assertEqual(
                presentation.accounts[0].status.resetCountdown(window: nil, now: now),
                "no data"
            )
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), "no data")
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, nil)
        },
        TestCase(name: "QuotaPresentationTests.testAvailableSourcePreservesPerAccountFreshness") {
            let cachedAt = now.addingTimeInterval(-300)
            let accounts = [
                account(
                    id: "one", alias: "max", active: true, inner: 27, outer: 59,
                    state: .stale(lastSuccessAt: cachedAt)),
                account(
                    id: "two", alias: "pro", active: false, inner: 88, outer: 76,
                    state: .fresh),
            ]

            let presentation = DashboardPresentation(
                snapshot: QuotaSnapshot(
                    claude: .available(accounts, updatedAt: now),
                    codex: .unavailable(message: "unavailable")
                )
            )

            try TestSupport.assertEqual(
                presentation.accounts[0].status,
                .stale(lastSuccessAt: cachedAt)
            )
            try TestSupport.assertEqual(presentation.accounts[1].status, .fresh)
        },
        TestCase(
            name: "QuotaPresentationTests.testLoadingProjectionKeepsPlaceholdersWithoutFailureCopy"
        ) {
            let presentation = DashboardPresentation(snapshot: .initial)

            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.accounts.map(\.fiveHour), [nil, nil])
            try TestSupport.assertEqual(presentation.accounts.map(\.weekly), [nil, nil])
            try TestSupport.assertEqual(
                presentation.accounts.map { $0.status.text(now: now) },
                [nil, nil]
            )
            try TestSupport.assertEqual(
                presentation.accounts[0].status.resetCountdown(window: nil, now: now),
                "—"
            )
            try TestSupport.assertEqual(presentation.codex.fiveHour, nil)
            try TestSupport.assertEqual(presentation.codex.weekly, nil)
            try TestSupport.assertEqual(
                presentation.codex.status.resetCountdown(window: nil, now: now),
                "—"
            )
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), nil)
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, nil)
        },
        TestCase(name: "QuotaBarTests.testUsedNormalizationClampsFillToTrack") {
            try TestSupport.assertEqual(QuotaBarMetrics.normalized(-5), 0)
            try TestSupport.assertEqual(QuotaBarMetrics.normalized(43), 43)
            try TestSupport.assertEqual(QuotaBarMetrics.normalized(105), 100)
            try TestSupport.assertEqual(QuotaBarMetrics.normalized(nil), 0)
        },
        TestCase(name: "QuotaBarTests.testAccessibilityDistinguishesAllStates") {
            try TestSupport.assertEqual(
                QuotaBarAccessibility.value(
                    window: "5 hours",
                    used: 72,
                    countdown: "resets in 3h 25m",
                    dataState: .available
                ),
                "5 hours, 72% used, resets in 3h 25m"
            )
            try TestSupport.assertEqual(
                QuotaBarAccessibility.value(
                    window: "5 hours",
                    used: 100,
                    countdown: "reset unavailable",
                    dataState: .available
                ),
                "5 hours, 100% used, reset unavailable"
            )
            try TestSupport.assertEqual(
                QuotaBarAccessibility.value(
                    window: "7 days",
                    used: nil,
                    countdown: "—",
                    dataState: .loading
                ),
                "7 days, loading"
            )
            try TestSupport.assertEqual(
                QuotaBarAccessibility.value(
                    window: "7 days",
                    used: nil,
                    countdown: "no data",
                    dataState: .unavailable
                ),
                "7 days, no data"
            )
        },
        TestCase(name: "SettingsViewTests.testLaunchAtLoginNoticeUsesNeutralCopy") {
            try TestSupport.assertEqual(
                LaunchAtLoginNotice.updated.text,
                "Setting saved"
            )
            try TestSupport.assertFalse(LaunchAtLoginNotice.updated.isFailure)
            try TestSupport.assertEqual(
                LaunchAtLoginNotice.updateFailed.text,
                "Could not change setting"
            )
            try TestSupport.assertTrue(LaunchAtLoginNotice.updateFailed.isFailure)
        },
    ]

    private static func window(remaining: Double, minutes: Double = 60) -> QuotaWindow {
        QuotaWindow(
            usedPercent: 100 - remaining,
            resetsAt: now.addingTimeInterval(minutes * 60)
        )
    }

    private static func account(
        id: String,
        alias: String,
        active: Bool,
        inner: Double,
        outer: Double,
        scoped: [ClaudeScopedQuota] = [],
        state: ClaudeAccountQuotaState = .fresh
    ) -> ClaudeAccountQuota {
        ClaudeAccountQuota(
            id: id,
            alias: alias,
            isActive: active,
            fiveHour: window(remaining: inner),
            weekly: window(remaining: outer),
            scoped: scoped,
            state: state
        )
    }

    private static func codex(remaining: Double) -> CodexQuota {
        CodexQuota(
            fiveHour: window(remaining: 25),
            weekly: window(remaining: remaining),
            creditsBalance: Decimal(string: "411.5127706250")
        )
    }
}
