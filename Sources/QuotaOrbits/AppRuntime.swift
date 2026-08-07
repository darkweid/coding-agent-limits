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

private actor MutableClaudeQuotaSource: ClaudeQuotaFetching {
    private var source: any ClaudeQuotaFetching
    private var replacementGeneration = 0

    init(source: any ClaudeQuotaFetching) {
        self.source = source
    }

    func fetch() async throws -> [ClaudeAccountQuota] {
        let source = source
        return try await source.fetch()
    }

    func replace(
        with source: any ClaudeQuotaFetching,
        generation: Int
    ) {
        guard generation >= replacementGeneration else { return }
        replacementGeneration = generation
        self.source = source
    }
}

private actor MutableCodexQuotaSource: CodexQuotaFetching {
    private var source: any CodexQuotaFetching
    private var transport: any JSONLineTransport
    private var replacementGeneration = 0

    init(
        source: any CodexQuotaFetching,
        transport: any JSONLineTransport
    ) {
        self.source = source
        self.transport = transport
    }

    func fetch() async throws -> CodexQuota {
        let source = source
        return try await source.fetch()
    }

    func replace(
        source: any CodexQuotaFetching,
        transport: any JSONLineTransport,
        generation: Int
    ) async {
        await self.transport.stop()
        guard generation >= replacementGeneration else {
            await transport.stop()
            return
        }
        replacementGeneration = generation
        self.source = source
        self.transport = transport
    }

    func stop() async {
        await transport.stop()
    }
}

@MainActor
final class AppRuntime {
    let coordinator: QuotaRefreshCoordinator

    private let preferences: PanelPreferences
    private let claudeSource: MutableClaudeQuotaSource
    private let codexSource: MutableCodexQuotaSource
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

        let claudeSource = MutableClaudeQuotaSource(
            source: ClaudeQuotaSource(
                executable: URL(fileURLWithPath: preferences.cswapPath)
            )
        )
        self.claudeSource = claudeSource

        let transport = ProcessJSONLineTransport(
            executable: URL(fileURLWithPath: preferences.codexPath),
            arguments: ["app-server"]
        )
        let codexSource = MutableCodexQuotaSource(
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
        guard path != preferences.cswapPath else { return }
        preferences.cswapPath = path
        cswapPathGeneration += 1
        let generation = cswapPathGeneration
        cswapPathTask?.cancel()
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
        guard path != preferences.codexPath else { return }
        preferences.codexPath = path
        codexPathGeneration += 1
        let generation = codexPathGeneration
        codexPathTask?.cancel()
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

        manualRefreshTask?.cancel()
        cswapPathTask?.cancel()
        codexPathTask?.cancel()
        await manualRefreshTask?.value
        await cswapPathTask?.value
        await codexPathTask?.value
        manualRefreshTask = nil
        cswapPathTask = nil
        codexPathTask = nil

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
        isAwake = false
        isStarted = false
        coordinator.stop()
        manualRefreshTask?.cancel()
        await waitForCoordinatorToStop()
        manualRefreshTask = nil
    }

    private func resumeAfterWake() async {
        guard !isShuttingDown else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        isAwake = true
        await waitForCoordinatorToStop()
        guard generation == lifecycleGeneration,
              isAwake,
              !isShuttingDown else { return }
        isStarted = true
        coordinator.start()
    }

    private func refreshAfterReconfiguration() async {
        while coordinator.isRefreshing, !Task.isCancelled {
            await Task.yield()
        }
        guard !Task.isCancelled, !isShuttingDown, isAwake else { return }
        await coordinator.refreshNow()
    }

    private func waitForCoordinatorToStop() async {
        while coordinator.isRefreshing {
            await Task.yield()
        }
    }
}
