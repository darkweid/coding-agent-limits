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

        let bucket =
            response.result.rateLimitsByLimitId?["codex"]
            ?? response.result.rateLimits
        let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }
        guard
            let weekly = windows.first(where: { $0.windowDurationMins == 10_080 }),
            let weeklyQuota = Self.quotaWindow(weekly)
        else {
            throw CodexQuotaError.missingPrimaryWindow
        }
        let fiveHour = windows.first(where: { $0.windowDurationMins == 300 })
        return CodexQuota(
            fiveHour: fiveHour.flatMap(Self.quotaWindow),
            weekly: weeklyQuota,
            creditsBalance: bucket?.credits?.balance.flatMap {
                Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
            }
        )
    }

    private static func quotaWindow(_ window: RateLimitWindow) -> QuotaWindow? {
        guard let resetsAt = window.resetsAt else { return nil }
        return QuotaWindow(
            usedPercent: window.usedPercent,
            resetsAt: Date(timeIntervalSince1970: resetsAt)
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
    let secondary: RateLimitWindow?
    let credits: Credits?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: TimeInterval?
}

private struct Credits: Decodable {
    let balance: String?
}
