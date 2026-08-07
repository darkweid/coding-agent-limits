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

    deinit {
        removeAll()
    }
}

@MainActor
final class AppRuntime {
    let coordinator: QuotaRefreshCoordinator

    private let preferences: PanelPreferences
    private let claudeSource: ReplaceableClaudeQuotaSource
    private let codexSource: ReplaceableCodexQuotaSource
    private let workspaceObservers = WorkspaceNotificationBag(
        center: NSWorkspace.shared.notificationCenter
    )
    private var manualRefreshTask: Task<Void, Never>?
    private var cswapPathTask: Task<Void, Never>?
    private var codexPathTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var cswapPathGeneration = 0
    private var codexPathGeneration = 0
    private var isAwake = true
    private var isStarted = false
    private var isShuttingDown = false

    init(preferences: PanelPreferences) {
        self.preferences = preferences

        let claudeSource = ReplaceableClaudeQuotaSource(
            source: ClaudeQuotaSource(
                executable: URL(fileURLWithPath: preferences.cswapPath)
            )
        )
        self.claudeSource = claudeSource

        let transport = ProcessJSONLineTransport(
            executable: URL(fileURLWithPath: preferences.codexPath),
            arguments: ["app-server"]
        )
        let codexSource = ReplaceableCodexQuotaSource(
            source: CodexQuotaSource(
                client: CodexAppServerClient(transport: transport)
            ),
            transport: transport
        )
        self.codexSource = codexSource
        coordinator = QuotaRefreshCoordinator(
            claude: claudeSource,
            codex: codexSource,
            ticker: MinuteTicker()
        )

        installWorkspaceObservers()
    }

    func start() {
        guard !isShuttingDown, !isStarted, isAwake else { return }
        isStarted = true
        coordinator.start()
    }

    func requestRefresh() {
        guard !isShuttingDown, isAwake else { return }
        guard manualRefreshTask == nil else { return }
        manualRefreshTask = Task { [weak self] in
            guard let self else { return }
            await coordinator.refreshNow()
            manualRefreshTask = nil
        }
    }

    func updateCswapPath(_ path: String) {
        guard !isShuttingDown, path != preferences.cswapPath else { return }
        preferences.cswapPath = path
        cswapPathGeneration += 1
        let generation = cswapPathGeneration
        cswapPathTask?.cancel()
        guard isAwake else { return }
        let source = claudeSource

        cswapPathTask = Task { [weak self] in
            await source.replace(
                with: ClaudeQuotaSource(
                    executable: URL(fileURLWithPath: path)
                ),
                generation: generation
            )
            guard let self, !Task.isCancelled else { return }
            await refreshAfterReconfiguration()
            if generation == cswapPathGeneration {
                cswapPathTask = nil
            }
        }
    }

    func updateCodexPath(_ path: String) {
        guard !isShuttingDown, path != preferences.codexPath else { return }
        preferences.codexPath = path
        codexPathGeneration += 1
        let generation = codexPathGeneration
        codexPathTask?.cancel()
        guard isAwake else { return }
        let source = codexSource

        codexPathTask = Task { [weak self] in
            let transport = ProcessJSONLineTransport(
                executable: URL(fileURLWithPath: path),
                arguments: ["app-server"]
            )
            await source.replace(
                source: CodexQuotaSource(
                    client: CodexAppServerClient(transport: transport)
                ),
                transport: transport,
                generation: generation
            )
            guard let self, !Task.isCancelled else { return }
            await refreshAfterReconfiguration()
            if generation == codexPathGeneration {
                codexPathTask = nil
            }
        }
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        isAwake = false
        isStarted = false
        lifecycleGeneration += 1
        removeWorkspaceObservers()
        coordinator.stop()

        await cancelRefreshOwningTasks()
        await waitForCoordinatorToStop()
        await codexSource.stop()
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.prepareForSleep()
                }
            }
        )
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.resumeAfterWake()
                }
            }
        )
    }

    private func removeWorkspaceObservers() {
        workspaceObservers.removeAll()
    }

    private func prepareForSleep() async {
        guard !isShuttingDown else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isAwake = false
        isStarted = false
        coordinator.stop()
        await cancelRefreshOwningTasks()
        await waitForCoordinatorToStop()
        guard generation == lifecycleGeneration,
              !isAwake,
              !isShuttingDown else { return }
        await reinstallPersistedSources()
    }

    private func resumeAfterWake() async {
        guard !isShuttingDown else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isAwake = true
        await waitForCoordinatorToStop()
        await reinstallPersistedSources()
        guard generation == lifecycleGeneration,
              isAwake,
              !isShuttingDown else { return }
        isStarted = true
        coordinator.start()
    }

    private func refreshAfterReconfiguration() async {
        await coordinator.waitUntilIdle()
        guard !Task.isCancelled, !isShuttingDown, isAwake else { return }
        await coordinator.refreshNow()
    }

    private func waitForCoordinatorToStop() async {
        await coordinator.waitUntilIdle()
    }

    private func cancelRefreshOwningTasks() async {
        let pendingManualRefresh = manualRefreshTask
        let pendingCswapPath = cswapPathTask
        let pendingCodexPath = codexPathTask
        pendingManualRefresh?.cancel()
        pendingCswapPath?.cancel()
        pendingCodexPath?.cancel()
        await pendingManualRefresh?.value
        await pendingCswapPath?.value
        await pendingCodexPath?.value
        self.manualRefreshTask = nil
        self.cswapPathTask = nil
        self.codexPathTask = nil
    }

    private func reinstallPersistedSources() async {
        cswapPathGeneration += 1
        let cswapGeneration = cswapPathGeneration
        await claudeSource.replace(
            with: ClaudeQuotaSource(
                executable: URL(fileURLWithPath: preferences.cswapPath)
            ),
            generation: cswapGeneration
        )

        codexPathGeneration += 1
        let codexGeneration = codexPathGeneration
        let transport = ProcessJSONLineTransport(
            executable: URL(fileURLWithPath: preferences.codexPath),
            arguments: ["app-server"]
        )
        await codexSource.replace(
            source: CodexQuotaSource(
                client: CodexAppServerClient(transport: transport)
            ),
            transport: transport,
            generation: codexGeneration
        )
    }
}
