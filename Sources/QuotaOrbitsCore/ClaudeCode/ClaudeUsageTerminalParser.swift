import Foundation

public enum ClaudeUsageTerminalParseError: Error, Equatable, Sendable {
    case invalidResponse
    case outputTooLarge
}

public struct ClaudeUsageTerminalParser: Sendable {
    public static let maximumOutputBytes = 65_536

    public init() {}

    public func parse(_ data: Data, now: Date = Date()) throws -> [QuotaLimit] {
        guard data.count <= Self.maximumOutputBytes else {
            throw ClaudeUsageTerminalParseError.outputTooLarge
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ClaudeUsageTerminalParseError.invalidResponse
        }

        let text = try sanitized(decoded)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var session: ParsedRow?
        var weekly: ParsedRow?
        var scoped: [ParsedRow] = []

        for (index, line) in lines.enumerated() {
            let heading = line.lowercased()
            guard heading == "current session" || heading.hasPrefix("current week") else {
                continue
            }
            let end =
                lines[(index + 1)...].firstIndex(where: {
                    let candidate = $0.lowercased()
                    return candidate == "current session" || candidate.hasPrefix("current week")
                        || candidate == "esc to exit"
                }) ?? lines.endIndex
            let block = Array(lines[(index + 1)..<end])
            guard let percent = parsePercent(in: block) else {
                throw ClaudeUsageTerminalParseError.invalidResponse
            }
            let reset = block.first(where: { $0.lowercased().hasPrefix("resets ") })
                .flatMap { parseReset(String($0.dropFirst("Resets ".count)), now: now) }

            if heading == "current session" {
                session = ParsedRow(label: "5 hours", percent: percent, reset: reset)
            } else if heading.contains("all models") {
                weekly = ParsedRow(label: "Weekly", percent: percent, reset: reset)
            } else if let label = scopedLabel(from: line) {
                scoped.append(ParsedRow(label: label, percent: percent, reset: reset))
            }
        }

        guard
            let session,
            let sessionReset = session.reset,
            let weekly,
            let weeklyReset = weekly.reset
        else {
            throw ClaudeUsageTerminalParseError.invalidResponse
        }

        let base = [
            QuotaLimit(
                id: "five-hour",
                label: session.label,
                usedPercent: session.percent,
                resetsAt: sessionReset
            ),
            QuotaLimit(
                id: "weekly",
                label: weekly.label,
                usedPercent: weekly.percent,
                resetsAt: weeklyReset
            ),
        ]
        let scopedLimits = try scoped.enumerated().map { index, row in
            guard isValidLabel(row.label) else {
                throw ClaudeUsageTerminalParseError.invalidResponse
            }
            return QuotaLimit(
                id: "scoped-\(index + 1)",
                label: row.label,
                usedPercent: row.percent,
                resetsAt: row.reset ?? weeklyReset
            )
        }
        return base + scopedLimits
    }

    private func sanitized(_ value: String) throws -> String {
        let ansiPattern = "\u{001B}\\[[0-?]*[ -/]*[@-~]"
        guard let regex = try? NSRegularExpression(pattern: ansiPattern) else {
            throw ClaudeUsageTerminalParseError.invalidResponse
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let stripped = regex.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: ""
        )
        for scalar in stripped.unicodeScalars {
            if scalar.value == 0x1B {
                throw ClaudeUsageTerminalParseError.invalidResponse
            }
            if CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n" && scalar != "\r" && scalar != "\t"
            {
                throw ClaudeUsageTerminalParseError.invalidResponse
            }
        }
        return stripped.replacingOccurrences(of: "\r", with: "\n")
    }

    private func parsePercent(in lines: [String]) -> Double? {
        let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)%\s*used"#)
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let match = regex?.firstMatch(in: line, range: range),
                let valueRange = Range(match.range(at: 1), in: line),
                let value = Double(line[valueRange]),
                value.isFinite,
                (0...100).contains(value)
            else {
                continue
            }
            return value
        }
        return nil
    }

    private func scopedLabel(from heading: String) -> String? {
        guard
            let open = heading.firstIndex(of: "("),
            let close = heading[open...].firstIndex(of: ")")
        else {
            return nil
        }
        let label = String(heading[heading.index(after: open)..<close])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.caseInsensitiveCompare("all models") == .orderedSame ? nil : label
    }

    private func parseReset(_ description: String, now: Date) -> Date? {
        let timezoneRange = description.range(of: #"\(([^)]+)\)$"#, options: .regularExpression)
        let timezoneID = timezoneRange.map {
            String(description[$0]).dropFirst().dropLast()
        }.map(String.init)
        let timeZone = timezoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let value =
            timezoneRange.map { String(description[..<$0.lowerBound]) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? description

        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.dateComponents(in: timeZone, from: now).year
        for format in ["MMM d 'at' h:mma", "MMM d, h:mma"] {
            guard let year else { continue }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy \(format)"
            if let parsed = formatter.date(from: "\(year) \(value)") {
                if parsed >= now { return parsed }
                return calendar.date(byAdding: .year, value: 1, to: parsed)
            }
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "h:mma"
        guard let time = timeFormatter.date(from: value) else { return nil }
        var components = calendar.dateComponents(in: timeZone, from: now)
        let timeComponents = calendar.dateComponents(in: timeZone, from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        guard let today = calendar.date(from: components) else { return nil }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    private func isValidLabel(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 40
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

private struct ParsedRow {
    let label: String
    let percent: Double
    let reset: Date?
}
