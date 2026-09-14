import Foundation

@_spi(Testing)
public enum ExecutablePathResolver {
    public static func defaultCswapPath(homeDirectory: URL) -> String {
        userLocalExecutable(named: "cswap", homeDirectory: homeDirectory)
    }

    public static func defaultClaudePath(
        homeDirectory: URL,
        isExecutable: (String) -> Bool
    ) -> String {
        preferredExecutablePath(
            named: "claude",
            homeDirectory: homeDirectory,
            isExecutable: isExecutable
        )
    }

    public static func defaultCodexPath(
        homeDirectory: URL,
        isExecutable: (String) -> Bool
    ) -> String {
        preferredExecutablePath(
            named: "codex",
            homeDirectory: homeDirectory,
            isExecutable: isExecutable
        )
    }

    private static func preferredExecutablePath(
        named name: String,
        homeDirectory: URL,
        isExecutable: (String) -> Bool
    ) -> String {
        let userLocalPath = userLocalExecutable(named: name, homeDirectory: homeDirectory)
        let candidates = [
            userLocalPath,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        return candidates.first(where: isExecutable) ?? userLocalPath
    }

    private static func userLocalExecutable(
        named name: String,
        homeDirectory: URL
    ) -> String {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
            .path
    }
}
