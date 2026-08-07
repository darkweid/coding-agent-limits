import Foundation
import QuotaOrbitsCore

actor MockCommandRunner: CommandRunning {
    let result: CommandResult
    private(set) var lastExecutable: URL?
    private(set) var lastArguments: [String]?

    init(result: CommandResult) {
        self.result = result
    }

    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> CommandResult {
        lastExecutable = executable
        lastArguments = arguments
        return result
    }
}
