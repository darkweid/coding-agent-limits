import Foundation

public actor ReplaceableClaudeQuotaSource: ClaudeQuotaFetching {
    private var source: any ClaudeQuotaFetching
    private var replacementGeneration = 0

    public init(source: any ClaudeQuotaFetching) {
        self.source = source
    }

    public func fetch() async throws -> [ClaudeAccountQuota] {
        let source = source
        return try await source.fetch()
    }

    public func replace(
        with source: any ClaudeQuotaFetching,
        generation: Int
    ) {
        guard generation > replacementGeneration else { return }
        replacementGeneration = generation
        self.source = source
    }
}

public actor ReplaceableCodexQuotaSource: CodexQuotaFetching {
    private var source: any CodexQuotaFetching
    private var transport: any JSONLineTransport
    private var replacementGeneration = 0

    public init(
        source: any CodexQuotaFetching,
        transport: any JSONLineTransport
    ) {
        self.source = source
        self.transport = transport
    }

    public func fetch() async throws -> CodexQuota {
        let source = source
        return try await source.fetch()
    }

    public func replace(
        source incomingSource: any CodexQuotaFetching,
        transport incomingTransport: any JSONLineTransport,
        generation: Int
    ) async {
        guard generation > replacementGeneration else {
            await incomingTransport.stop()
            return
        }

        replacementGeneration = generation
        let priorTransport = transport
        source = incomingSource
        transport = incomingTransport
        await priorTransport.stop()
    }

    public func stop() async {
        let activeTransport = transport
        await activeTransport.stop()
    }
}
