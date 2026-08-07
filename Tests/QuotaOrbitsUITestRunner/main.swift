import Darwin
import Foundation

let filter: String?
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    filter = nil
} else if arguments.count == 2, arguments[0] == "--filter" {
    filter = arguments[1]
} else {
    print("usage: QuotaOrbitsUITestRunner [--filter <substring>]")
    exit(2)
}

let allCases = QuotaPaletteTests.cases
    + QuotaPresentationTests.cases
    + PanelPreferencesTests.cases
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
