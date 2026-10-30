import Foundation

/// A complete log parsed once for display and copying.
public struct CheckLogDocument: Sendable {
    // MARK: Lifecycle

    public init(_ log: String) {
        var parsed = [Line]()
        var groups = [Int]()
        for raw in log.replacing("\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let plain = CheckLog.strippingANSI(String(raw))
            let body = CheckLog.stripped(plain)
            if body == "##[endgroup]" {
                if let start = groups.popLast() {
                    parsed[start].endIndex = parsed.count
                }
                continue
            }
            let marker = body.hasPrefix("##[group]") ? "##[group]" : nil
            let command = ["##[command]", "[command]"].first { body.hasPrefix($0) }
            let level = Level.allCases.first { body.hasPrefix("##[" + $0.rawValue + "]") }
            parsed.append(Line(
                timestamp: String(plain.dropLast(body.count)),
                text: (marker ?? command ?? level.map { "##[" + $0.rawValue + "]" })
                    .map { String(body.dropFirst($0.count)) } ?? body,
                depth: groups.count,
                isCommand: command != nil,
                level: level,
                endIndex: marker == nil ? nil : .max,
            ))
            if marker != nil {
                groups.append(parsed.count - 1)
            }
        }
        for start in groups {
            parsed[start].endIndex = parsed.count
        }
        lines = parsed
    }

    // MARK: Public

    // SwiftFormat removes raw values identical to the runner's tag names.
    // swiftlint:disable explicit_enum_raw_value
    /// A diagnostic level emitted in a processed Actions log.
    public enum Level: String, CaseIterable, Sendable {
        case debug
        case notice
        case warning
        case error
    }

    // swiftlint:enable explicit_enum_raw_value

    public struct Line: Sendable {
        // MARK: Public

        public let timestamp: String
        public let text: String
        public let depth: Int
        public let isCommand: Bool
        public let level: Level?
        public internal(set) var endIndex: Int?

        public func displayed(showTimestamps: Bool) -> String {
            String(repeating: "  ", count: min(depth, Self.maximumIndentDepth))
                + (showTimestamps ? timestamp : "")
                + (level.map { $0.rawValue.capitalized + ": " } ?? "") + text
        }

        // MARK: Private

        private static let maximumIndentDepth = 8
    }

    public let lines: [Line]

    public func visibleIndices(collapsedGroups: Set<Int>) -> [Int] {
        var visible = [Int]()
        var next = 0
        while next < lines.count {
            visible.append(next)
            next = collapsedGroups.contains(next) ? (lines[next].endIndex ?? next + 1) : next + 1
        }
        return visible
    }

    /// Copies every group, regardless of which are collapsed on screen.
    public func plainText(showTimestamps: Bool) -> String {
        lines.lazy.map { $0.displayed(showTimestamps: showTimestamps) }.joined(separator: "\n")
    }
}
