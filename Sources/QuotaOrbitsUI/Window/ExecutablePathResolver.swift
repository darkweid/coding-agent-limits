import Foundation

@_spi(Testing)
public enum ExecutablePathResolver {
    public static func defaultCswapPath(homeDirectory: URL) -> String {
        userLocalExecutable(named: "cswap", homeDirectory: homeDirectory)
    }

    public static func defaultCodexPath(
        homeDirectory: URL,
        isExecutable: (String) -> Bool
    ) -> String {
        let userLocalPath = userLocalExecutable(
            named: "codex",
            homeDirectory: homeDirectory
        )
        let candidates = [
            userLocalPath,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
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
