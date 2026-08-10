import OSLog

public enum SourceKind: String, Sendable {
    case claude
    case codex
}

public enum FailureCategory: String, Sendable {
    case timeout
    case launch
    case exitCode
    case transport
    case invalidResponse
}

public enum SafeLogger {
    @_spi(Testing)
    public static let subsystem = "io.github.darkweid.coding-agent-limits"

    private static let logger = Logger(
        subsystem: subsystem,
        category: "quota-refresh"
    )

    public static func cycleStarted() {
        logger.info("Quota refresh cycle started")
    }

    public static func sourceSucceeded(_ source: SourceKind) {
        logger.info("Quota source succeeded: \(source.rawValue, privacy: .public)")
    }

    public static func sourceFailed(
        _ source: SourceKind,
        category: FailureCategory
    ) {
        logger.error(
            "Quota source failed: \(source.rawValue, privacy: .public), category: \(category.rawValue, privacy: .public)"
        )
    }

    public static func appServerRestarted() {
        logger.info("Codex app-server restarted")
    }
}
