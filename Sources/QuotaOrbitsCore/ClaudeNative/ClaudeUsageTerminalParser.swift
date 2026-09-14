import Foundation

public enum ClaudeUsageTerminalParseError: Error, Equatable, Sendable {
    case invalidResponse
    case outputTooLarge
}

public struct ClaudeNativeUsage: Equatable, Sendable {
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let scoped: [ClaudeScopedQuota]
}

public struct ClaudeUsageTerminalParser: Sendable {
    public static let maximumOutputBytes = 65_536

    public init() {}

    public func parse(_ data: Data, now: Date = Date()) throws -> ClaudeNativeUsage {
        guard data.count <= Self.maximumOutputBytes else {
            throw ClaudeUsageTerminalParseError.outputTooLarge
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ClaudeUsageTerminalParseError.invalidResponse
        }

        let lines = try sanitized(decoded)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var fiveHour: ParsedRow?
        var weekly: ParsedRow?
        var scoped: [ParsedRow] = []

        for (index, line) in lines.enumerated() {
            let heading = line.lowercased()
            guard heading == "current session" || heading.hasPrefix("current week") else {
                continue
            }
            let blockStart = index + 1
            let remaining = blockStart < lines.count ? lines[blockStart...] : []
            let block = Array(
                remaining.prefix { candidate in
                    let normalized = candidate.lowercased()
                    return normalized != "current session"
                        && !normalized.hasPrefix("current week")
                        && !normalized.contains("esc to exit")
                        && !normalized.contains("esc to go back")
                }
            )
            guard let percent = parsePercent(in: block) else { continue }
            let reset = block.first(where: { $0.lowercased().hasPrefix("resets ") })
                .flatMap { parseReset(String($0.dropFirst("Resets ".count)), now: now) }
            let row = ParsedRow(percent: percent, reset: reset)

            if heading == "current session" {
                fiveHour = row
            } else if heading.contains("all models") {
                weekly = row
            } else if let label = scopedLabel(from: line), isValidLabel(label) {
                scoped.append(ParsedRow(label: label, percent: percent, reset: reset))
            }
        }

        guard fiveHour != nil || weekly != nil else {
            throw ClaudeUsageTerminalParseError.invalidResponse
        }

        let weeklyReset = weekly?.reset
        return ClaudeNativeUsage(
            fiveHour: fiveHour.map { QuotaWindow(usedPercent: $0.percent, resetsAt: $0.reset) },
            weekly: weekly.map { QuotaWindow(usedPercent: $0.percent, resetsAt: $0.reset) },
            scoped: scoped.map {
                ClaudeScopedQuota(
                    label: $0.label,
                    window: QuotaWindow(
                        usedPercent: $0.percent,
                        resetsAt: $0.reset ?? weeklyReset
                    )
                )
            }
        )
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
        let regex = try? NSRegularExpression(
            pattern: #"([0-9]+(?:\.[0-9]+)?)%\s*used"#,
            options: .caseInsensitive
        )
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard
                let match = regex?.firstMatch(in: line, range: range),
                let valueRange = Range(match.range(at: 1), in: line),
                let value = Double(line[valueRange]),
                value.isFinite,
                (0...100).contains(value)
            else { continue }
            return value
        }
        return nil
    }

    private func scopedLabel(from heading: String) -> String? {
        guard
            let open = heading.firstIndex(of: "("),
            let close = heading[open...].firstIndex(of: ")")
        else { return nil }
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
            && !value.contains("@")
            && value.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}

private struct ParsedRow {
    var label = ""
    let percent: Double
    let reset: Date?
}
