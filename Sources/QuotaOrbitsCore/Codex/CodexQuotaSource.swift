import Foundation

public enum CodexQuotaError: Error, Equatable, Sendable {
    case invalidResponse
    case missingPrimaryWindow
}

public actor CodexQuotaSource: CodexQuotaFetching {
    private let client: CodexAppServerClient

    public init() {
        self.client = CodexAppServerClient()
    }

    public init(client: CodexAppServerClient) {
        self.client = client
    }

    public func fetch() async throws -> CodexQuota {
        let line = try await client.rateLimitsResponse()
        let response: RateLimitsRPCResponse
        do {
            response = try JSONDecoder().decode(
                RateLimitsRPCResponse.self,
                from: line
            )
        } catch {
            throw CodexQuotaError.invalidResponse
        }

        let bucket = response.result.rateLimitsByLimitId?["codex"]
            ?? response.result.rateLimits
        guard let primary = bucket?.primary else {
            throw CodexQuotaError.missingPrimaryWindow
        }
        return CodexQuota(
            weekly: QuotaWindow(
                usedPercent: primary.usedPercent,
                resetsAt: Date(timeIntervalSince1970: primary.resetsAt)
            ),
            creditsBalance: bucket?.credits?.balance.flatMap {
                Decimal(string: $0)
            }
        )
    }
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
