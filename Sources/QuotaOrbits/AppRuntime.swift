import AppKit
import Foundation
import QuotaOrbitsCore
import QuotaOrbitsUI

private final class WorkspaceNotificationBag: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter) {
        self.center = center
    }

    func append(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    func removeAll() {
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }

    deinit { removeAll() }
}

@MainActor
final class AppRuntime {
    let coordinator: QuotaFeedRefreshCoordinator

    private let preferences: AppPreferences
    private let claudeSource: ReplaceableQuotaSource
    private let codexSource: ReplaceableQuotaSource
    private let workspaceObservers = WorkspaceNotificationBag(
        center: NSWorkspace.shared.notificationCenter
    )
    private var manualRefreshTask: Task<Void, Never>?
    private var claudeConfigurationTask: Task<Void, Never>?
    private var codexConfigurationTask: Task<Void, Never>?
    private var claudeGeneration = 0
    private var codexGeneration = 0
    private var isAwake = true
    private var isStarted = false
    private var isShuttingDown = false

    init(preferences: AppPreferences) {
        self.preferences = preferences
        let initialClaude = Self.makeClaudeSource(preferences: preferences)
        let claudeSlot = ReplaceableQuotaSource(source: initialClaude)
        claudeSource = claudeSlot

        let codexComponents = Self.makeCodexSource(path: preferences.codexPath)
        let codexSlot = ReplaceableQuotaSource(
            source: codexComponents.source,
            cleanup: codexComponents.cleanup
        )
        codexSource = codexSlot
        coordinator = QuotaFeedRefreshCoordinator(
            sources: [claudeSlot, codexSlot],
            ticker: IntervalTicker(),
            refreshInterval: .seconds(preferences.refreshIntervalSeconds)
        )
        installWorkspaceObservers()
    }

    func start() {
        guard !isShuttingDown, !isStarted, isAwake else { return }
        isStarted = true
        coordinator.start()
    }

    func requestRefresh() {
        guard !isShuttingDown, isAwake, manualRefreshTask == nil else { return }
        manualRefreshTask = Task { [weak self] in
            guard let self else { return }
            await coordinator.refreshNow()
            manualRefreshTask = nil
        }
    }

    func updateClaudeSourceMode(_ mode: ClaudeSourceMode) {
        guard mode != preferences.claudeSourceMode else { return }
        preferences.claudeSourceMode = mode
        replaceClaudeSource()
    }

    func updateCswapPath(_ path: String) {
        guard path != preferences.cswapPath else { return }
        preferences.cswapPath = path
        if preferences.claudeSourceMode == .cswap { replaceClaudeSource() }
    }

    func updateClaudePath(_ path: String) {
        guard path != preferences.claudePath else { return }
        preferences.claudePath = path
        if preferences.claudeSourceMode == .nativeClaudeCode { replaceClaudeSource() }
    }

    func updateCodexPath(_ path: String) {
        guard path != preferences.codexPath else { return }
        preferences.codexPath = path
        codexGeneration += 1
        let generation = codexGeneration
        codexConfigurationTask?.cancel()
        guard isAwake, !isShuttingDown else { return }
        let components = Self.makeCodexSource(path: path)
        codexConfigurationTask = Task { [weak self] in
            guard let self else {
                await components.cleanup()
                return
            }
            await coordinator.waitUntilIdle()
            guard !Task.isCancelled else {
                await components.cleanup()
                return
            }
            await codexSource.replace(
                with: components.source,
                generation: generation,
                cleanup: components.cleanup
            )
            guard !Task.isCancelled else { return }
            await coordinator.refreshNow()
            if generation == codexGeneration { codexConfigurationTask = nil }
        }
    }

    func updateRefreshInterval(_ seconds: Int) {
        guard seconds != preferences.refreshIntervalSeconds else { return }
        preferences.refreshIntervalSeconds = seconds
        coordinator.updateRefreshInterval(.seconds(preferences.refreshIntervalSeconds))
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        isAwake = false
        isStarted = false
        removeWorkspaceObservers()
        await cancelOwnedTasks()
        await coordinator.stop()
        await claudeSource.stop()
        await codexSource.stop()
    }

    private func replaceClaudeSource() {
        claudeGeneration += 1
        let generation = claudeGeneration
        claudeConfigurationTask?.cancel()
        guard isAwake, !isShuttingDown else { return }
        let source = Self.makeClaudeSource(preferences: preferences)
        claudeConfigurationTask = Task { [weak self] in
            guard let self else { return }
            await coordinator.waitUntilIdle()
            guard !Task.isCancelled else { return }
            await claudeSource.replace(with: source, generation: generation)
            guard !Task.isCancelled else { return }
            await coordinator.refreshNow()
            if generation == claudeGeneration { claudeConfigurationTask = nil }
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.prepareForSleep() }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.resumeAfterWake() }
            }
        )
    }

    private func removeWorkspaceObservers() {
        workspaceObservers.removeAll()
    }

    private func prepareForSleep() async {
        guard !isShuttingDown else { return }
        isAwake = false
        isStarted = false
        await cancelOwnedTasks()
        await coordinator.stop()
        await claudeSource.stop()
        await codexSource.stop()
    }

    private func resumeAfterWake() {
        guard !isShuttingDown else { return }
        isAwake = true
        reinstallSources()
        isStarted = true
        coordinator.start()
    }

    private func reinstallSources() {
        replaceClaudeSource()
        updateCodexPathAfterWake(preferences.codexPath)
    }

    private func updateCodexPathAfterWake(_ path: String) {
        codexGeneration += 1
        let generation = codexGeneration
        let components = Self.makeCodexSource(path: path)
        codexConfigurationTask = Task { [weak self] in
            guard let self else {
                await components.cleanup()
                return
            }
            await codexSource.replace(
                with: components.source,
                generation: generation,
                cleanup: components.cleanup
            )
            if generation == codexGeneration { codexConfigurationTask = nil }
        }
    }

    private func cancelOwnedTasks() async {
        let tasks = [manualRefreshTask, claudeConfigurationTask, codexConfigurationTask]
        tasks.forEach { $0?.cancel() }
        for task in tasks { await task?.value }
        manualRefreshTask = nil
        claudeConfigurationTask = nil
        codexConfigurationTask = nil
    }

    private static func makeClaudeSource(preferences: AppPreferences) -> any QuotaSource {
        switch preferences.claudeSourceMode {
        case .cswap:
            CswapQuotaSource(executable: URL(fileURLWithPath: preferences.cswapPath))
        case .nativeClaudeCode:
            ClaudeCodeQuotaSource(executable: URL(fileURLWithPath: preferences.claudePath))
        }
    }

    private static func makeCodexSource(path: String) -> (
        source: any QuotaSource,
        cleanup: @Sendable () async -> Void
    ) {
        let transport = ProcessJSONLineTransport(
            executable: URL(fileURLWithPath: path),
            arguments: ["app-server"]
        )
        return (
            CodexAppServerQuotaSource(
                client: CodexAppServerClient(transport: transport)
            ),
            { await transport.stop() }
        )
    }
}
