import Darwin
import Foundation

let filter: String?
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--emit-large-payload"] {
    FileHandle.standardOutput.write(Data(repeating: 0x78, count: 1_000_000))
    exit(0)
} else if arguments == ["--emit-usage-pty"] {
    print("❯")
    fflush(stdout)
    while let line = readLine() {
        if line == "/usage" {
            print("Current session")
            print("9% used")
            print("Resets 11:59pm (UTC)")
            print("Current week (all models)")
            print("20% used")
            print("Resets Aug 14 at 10:59am (UTC)")
            print("Esc to exit")
            fflush(stdout)
        } else if line == "/exit" {
            exit(0)
        }
    }
    exit(0)
} else if arguments == ["--emit-terminal-size-usage-pty"] {
    var size = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 else { exit(3) }
    print("viewport \(size.ws_row)x\(size.ws_col)")
    print("❯")
    fflush(stdout)
    while let line = readLine() {
        if line == "/usage" {
            print("Current session")
            print("9% used")
            print("Resets 11:59pm (UTC)")
            print("Current week (all models)")
            print("20% used")
            print("Resets Aug 14 at 10:59am (UTC)")
            print("Esc to exit")
            fflush(stdout)
        } else if line == "/exit" {
            exit(0)
        }
    }
    exit(0)
} else if arguments == ["--emit-trust-usage-pty"] {
    print("Workspace trust security")
    print("❯ Yes, I trust this folder")
    fflush(stdout)
    guard readLine() == "\u{1B}[B" else { exit(3) }
    print("❯")
    fflush(stdout)
    while let line = readLine() {
        if line == "/usage" {
            print("Current session")
            print("9% used")
            print("Current week (all models)")
            print("20% used")
            print("Esc to exit")
            fflush(stdout)
        } else if line == "/exit" {
            exit(0)
        }
    }
    exit(0)
} else if arguments.isEmpty {
    filter = nil
} else if arguments.count == 2, arguments[0] == "--filter" {
    filter = arguments[1]
} else {
    print("usage: QuotaOrbitsCoreTestRunner [--filter <substring>]")
    exit(2)
}

let allCases =
    QuotaModelsTests.cases
    + QuotaFormattingTests.cases
    + ClaudeQuotaSourceTests.cases
    + ClaudeUsageTerminalParserTests.cases
    + ClaudeNativeQuotaSourceTests.cases
    + CodexAppServerClientTests.cases
    + CodexQuotaSourceTests.cases
    + QuotaRefreshCoordinatorTests.cases
    + ReplaceableQuotaSourceTests.cases
    + PrivacyBoundaryTests.cases
let selectedCases = allCases.filter { testCase in
    filter.map { testCase.name.localizedCaseInsensitiveContains($0) } ?? true
}

if selectedCases.isEmpty {
    print("No tests matched the filter.")
    exit(1)
}

var failures = 0
for testCase in selectedCases {
    do {
        try await testCase.body()
        print("PASS \(testCase.name)")
    } catch {
        failures += 1
        print("FAIL \(testCase.name): \(error)")
    }
}

print("Ran \(selectedCases.count) test(s), \(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
