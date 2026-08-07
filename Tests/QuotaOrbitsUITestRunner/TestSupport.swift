import Foundation

struct TestCase: Sendable {
    let name: String
    let body: @Sendable () async throws -> Void
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

    static func assertTrue(
        _ condition: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard condition else {
            throw AssertionFailure(message: "\(file):\(line): expected true")
        }
    }

    static func assertFalse(
        _ condition: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard !condition else {
            throw AssertionFailure(message: "\(file):\(line): expected false")
        }
    }
}
