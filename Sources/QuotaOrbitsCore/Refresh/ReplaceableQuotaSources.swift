import Foundation

public actor ReplaceableQuotaSource: QuotaSource {
    public nonisolated let sourceID: QuotaSourceID
    public nonisolated let providerID: ProviderID
    private var source: any QuotaSource
    private var cleanup: @Sendable () async -> Void
    private var replacementGeneration = 0

    public init(
        source: any QuotaSource,
        cleanup: @escaping @Sendable () async -> Void = {}
    ) {
        sourceID = source.sourceID
        providerID = source.providerID
        self.source = source
        self.cleanup = cleanup
    }

    public func fetch() async throws -> ProviderQuota {
        let source = source
        return try await source.fetch()
    }

    public func replace(
        with incomingSource: any QuotaSource,
        generation: Int,
        cleanup incomingCleanup: @escaping @Sendable () async -> Void = {}
    ) async {
        guard
            incomingSource.providerID == providerID,
            generation > replacementGeneration
        else {
            await incomingCleanup()
            return
        }

        replacementGeneration = generation
        let priorCleanup = cleanup
        source = incomingSource
        cleanup = incomingCleanup
        await priorCleanup()
    }

    public func stop() async {
        let activeCleanup = cleanup
        cleanup = {}
        await activeCleanup()
    }
}
