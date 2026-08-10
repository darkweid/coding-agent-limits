import Foundation

public enum CodexQuotaError: Error, Equatable, Sendable {
    case invalidResponse
    case missingPrimaryWindow
}

public actor CodexAppServerQuotaSource: QuotaSource {
    public nonisolated let sourceID = QuotaSourceID.codexAppServer
    public nonisolated let providerID = ProviderID.codex
    private let client: CodexAppServerClient

    public init() {
        self.client = CodexAppServerClient()
    }

    public init(client: CodexAppServerClient) {
        self.client = client
    }

    public func fetch() async throws -> ProviderQuota {
        let decoded = try await decodeCodexQuota(from: client)
        return ProviderQuota(
            providerID: providerID,
            accounts: [
                QuotaAccount(
                    id: "default",
                    alias: "",
                    isActive: true,
                    state: .fresh,
                    limits: [
                        QuotaLimit(
                            id: "weekly",
                            label: "Weekly",
                            usedPercent: decoded.usedPercent,
                            resetsAt: decoded.resetsAt
                        )
                    ]
                )
            ],
            balances: decoded.creditsBalance.map {
                [QuotaBalance(label: "Credits", amount: $0, currencyCode: nil)]
            } ?? []
        )
    }
}

private struct DecodedCodexQuota: Sendable {
    let usedPercent: Double
    let resetsAt: Date
    let creditsBalance: Decimal?
}

private func decodeCodexQuota(from client: CodexAppServerClient) async throws
    -> DecodedCodexQuota
{
    let line = try await client.rateLimitsResponse()
    let response: RateLimitsRPCResponse
    do {
        response = try JSONDecoder().decode(RateLimitsRPCResponse.self, from: line)
    } catch {
        throw CodexQuotaError.invalidResponse
    }

    let bucket = response.result.rateLimitsByLimitId?["codex"] ?? response.result.rateLimits
    guard
        let primary = bucket?.primary,
        primary.usedPercent.isFinite,
        (0...100).contains(primary.usedPercent),
        primary.resetsAt.isFinite
    else {
        throw CodexQuotaError.missingPrimaryWindow
    }
    return DecodedCodexQuota(
        usedPercent: primary.usedPercent,
        resetsAt: Date(timeIntervalSince1970: primary.resetsAt),
        creditsBalance: bucket?.credits?.balance.flatMap {
            Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
        }
    )
}

private struct RateLimitsRPCResponse: Decodable {
    let id: Int
    let result: RateLimitsResult
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitBucket?
    let rateLimitsByLimitId: [String: RateLimitBucket]?
}

private struct RateLimitBucket: Decodable {
    let primary: RateLimitWindow?
    let credits: Credits?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval
}

private struct Credits: Decodable {
    let balance: String?
}
