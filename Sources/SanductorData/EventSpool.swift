import Foundation

/// Reads the hook event spool the sandbox-side hook script appends
/// to, one JSONL file per session.
public struct EventSpool: Sendable {
    // MARK: Lifecycle

    /// Creates a spool reader for a directory.
    public init(directory: String) {
        self.directory = directory
    }

    // MARK: Public

    /// The last activity time of every session with spooled events.
    public func activity() -> [String: Date] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        var result = [String: Date]()
        for name in names where name.hasSuffix(".jsonl") {
            let path = directory + "/" + name
            let attributes = try? manager.attributesOfItem(atPath: path)
            let date = attributes?[.modificationDate] as? Date ?? .distantPast
            result[String(name.dropLast(".jsonl".count))] = date
        }
        return result
    }

    // MARK: Private

    private let directory: String
}
