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

    static func assertThrowsErrorAsync<Value>(
        _ expression: @autoclosure () async throws -> Value,
        _ errorHandler: (Error) throws -> Void
    ) async throws {
        do {
            _ = try await expression()
        } catch {
            try errorHandler(error)
            return
        }

        throw AssertionFailure(message: "expected expression to throw an error")
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

    static func fixtureData(
        _ name: String
    ) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            throw AssertionFailure(message: "missing fixture \(name)")
        }
        return try Data(contentsOf: url)
    }
}
