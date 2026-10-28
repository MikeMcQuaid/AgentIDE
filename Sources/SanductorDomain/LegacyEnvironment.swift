import Foundation
import Synchronization

/// Accepts old environment names without logging their values.
enum LegacyEnvironment {
    // MARK: Internal

    /// Prefers a canonical value, warning once when its legacy name is used.
    static func value(
        for name: String,
        warning: ((String) -> Void)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> String? {
        if let value = environment[name] {
            return value
        }
        let legacy = "AGENTIDE" + name.dropFirst("SANDUCTOR".count)
        guard let value = environment[legacy] else {
            return nil
        }

        let message = "Warning: " + legacy + " is deprecated; use " + name + " instead."
        if let warning {
            warning(message)
        } else if warned.withLock({ $0.insert(message).inserted }) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        return value
    }

    // MARK: Private

    private static let warned: Mutex<Set<String>> = .init([])
}
