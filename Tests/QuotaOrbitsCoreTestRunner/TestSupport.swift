import Foundation

struct TestCase {
    let name: String
    let body: () async throws -> Void
}

struct AssertionFailure: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
}

enum TestSupport {
    static func assertEqual<Value: Equatable>(
        _ actual: Value,
        _ expected: Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard actual == expected else {
            throw AssertionFailure(
                message: "\(file):\(line): expected \(expected), got \(actual)"
            )
        }
    }
}
