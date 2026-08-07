import Foundation
import QuotaOrbitsCore
@_spi(Testing) import QuotaOrbitsUI

enum QuotaPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static let cases: [TestCase] = [
        TestCase(name: "QuotaPresentationTests.testQuotaCopyFormatsValuesForDisplay") {
            try TestSupport.assertEqual(QuotaCopy.percent(28.4), "28%")
            try TestSupport.assertEqual(QuotaCopy.percent(nil), "—")
            try TestSupport.assertEqual(
                QuotaCopy.reset(prefix: "5ч", window: window(remaining: 28, minutes: 205), now: now),
                "5ч · сброс через 3ч 25м"
            )
            try TestSupport.assertEqual(QuotaCopy.reset(prefix: "7д", window: nil, now: now), "7д · нет данных")
            try TestSupport.assertEqual(QuotaCopy.stale(lastSuccessAt: now.addingTimeInterval(-125), now: now), "обновлено 2 мин назад")
            try TestSupport.assertEqual(QuotaCopy.credits(Decimal(string: "411.5127706250")!), "411.51")
        },
        TestCase(name: "QuotaPresentationTests.testContextActionsUseNeutralApprovedCopy") {
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: true),
                ["Обновить сейчас", "Переместить", "Настройки…", "Выйти"]
            )
            try TestSupport.assertEqual(
                DashboardCopy.contextActions(isPinned: false),
                ["Обновить сейчас", "Закрепить", "Настройки…", "Выйти"]
            )
        },
        TestCase(name: "QuotaPresentationTests.testDashboardProjectionNeverRetainsIdentifiersOrErrors") {
            let accounts = [
                account(id: "private@example.com", alias: "private@example.com", active: true, inner: 100, outer: 81),
                account(id: "second@example.com", alias: "Claude Code", active: false, inner: 28, outer: 93)
            ]
            let snapshot = QuotaSnapshot(
                claude: .stale(accounts, lastSuccessAt: now.addingTimeInterval(-120), message: "token for private@example.com failed"),
                codex: .unavailable(message: "Codex transport includes technical details"),
                lastCycleStartedAt: now
            )

            let presentation = DashboardPresentation(snapshot: snapshot)

            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.accounts.map(\.id), ["slot-1", "slot-2"])
            try TestSupport.assertEqual(presentation.accounts[0].status.text(now: now), "обновлено 2 мин назад")
            try TestSupport.assertEqual(presentation.codex.symbol, "◇")
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), "нет данных")
        },
        TestCase(name: "QuotaPresentationTests.testDashboardProjectionKeepsTwoAliasesAndLatestSuccess") {
            let accounts = [
                account(id: "one", alias: "max", active: true, inner: 100, outer: 81),
                account(id: "two", alias: "очень-длинное-нейтральное-имя", active: false, inner: 28, outer: 93)
            ]
            let snapshot = QuotaSnapshot(
                claude: .available(accounts, updatedAt: now.addingTimeInterval(-60)),
                codex: .available(codex(remaining: 50), updatedAt: now),
                lastCycleStartedAt: now
            )

            let presentation = DashboardPresentation(snapshot: snapshot)

            try TestSupport.assertEqual(presentation.accounts.count, 2)
            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["max", "очень-длинное-нейтральное-имя"])
            try TestSupport.assertEqual(presentation.accounts.map(\.fiveHour?.remainingPercent), [100, 28])
            try TestSupport.assertEqual(presentation.accounts.map(\.weekly?.remainingPercent), [81, 93])
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
            try TestSupport.assertEqual(presentation.accounts.map { $0.status.text(now: now) }, ["нет данных", "нет данных"])
            try TestSupport.assertEqual(
                presentation.accounts[0].status.reset(prefix: "5ч", window: nil, now: now),
                "5ч · нет данных"
            )
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), "нет данных")
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, nil)
        },
        TestCase(name: "QuotaPresentationTests.testLoadingProjectionKeepsPlaceholdersWithoutFailureCopy") {
            let presentation = DashboardPresentation(snapshot: .initial)

            try TestSupport.assertEqual(presentation.accounts.map(\.alias), ["01", "02"])
            try TestSupport.assertEqual(presentation.accounts.map(\.fiveHour), [nil, nil])
            try TestSupport.assertEqual(presentation.accounts.map(\.weekly), [nil, nil])
            try TestSupport.assertEqual(
                presentation.accounts.map { $0.status.text(now: now) },
                [nil, nil]
            )
            try TestSupport.assertEqual(
                presentation.accounts[0].status.reset(prefix: "5ч", window: nil, now: now),
                "5ч · —"
            )
            try TestSupport.assertEqual(presentation.codex.weekly, nil)
            try TestSupport.assertEqual(
                presentation.codex.status.reset(prefix: "7д", window: nil, now: now),
                "7д · —"
            )
            try TestSupport.assertEqual(presentation.codex.status.text(now: now), nil)
            try TestSupport.assertEqual(presentation.lastSuccessfulRefreshAt, nil)
        },
        TestCase(name: "QuotaPresentationTests.testOrbitAccessibilityExplainsInnerAndOuterMeaning") {
            try TestSupport.assertEqual(
                OrbitGaugeAccessibility.label(hasInner: true),
                "Остаток лимита: внутреннее кольцо 5 часов, внешнее кольцо 7 дней"
            )
            try TestSupport.assertEqual(
                OrbitGaugeAccessibility.value(inner: 28, outer: 93),
                "5 часов — 28% осталось; 7 дней — 93% осталось"
            )
            try TestSupport.assertEqual(
                OrbitGaugeAccessibility.label(hasInner: false),
                "Остаток лимита: кольцо 7 дней"
            )
            try TestSupport.assertEqual(
                OrbitGaugeAccessibility.value(inner: nil, outer: nil),
                "7 дней — нет данных"
            )
        },
        TestCase(name: "SettingsViewTests.testLaunchAtLoginNoticeUsesNeutralCopy") {
            try TestSupport.assertEqual(
                LaunchAtLoginNotice.updated.text,
                "Настройка сохранена"
            )
            try TestSupport.assertFalse(LaunchAtLoginNotice.updated.isFailure)
            try TestSupport.assertEqual(
                LaunchAtLoginNotice.updateFailed.text,
                "Не удалось изменить настройку"
            )
            try TestSupport.assertTrue(LaunchAtLoginNotice.updateFailed.isFailure)
        }
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
        outer: Double
    ) -> ClaudeAccountQuota {
        ClaudeAccountQuota(
            id: id,
            alias: alias,
            isActive: active,
            fiveHour: window(remaining: inner),
            weekly: window(remaining: outer)
        )
    }

    private static func codex(remaining: Double) -> CodexQuota {
        CodexQuota(
            weekly: window(remaining: remaining),
            creditsBalance: Decimal(string: "411.5127706250")
        )
    }
}
