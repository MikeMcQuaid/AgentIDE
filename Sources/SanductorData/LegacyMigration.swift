import Foundation

/// Restores private state before any model opens the new locations.
public enum LegacyMigration {
    // MARK: Public

    /// Whether private state still needs its one-time migration.
    public static func isNeeded(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: completedKey) == false
    }

    /// Copies missing state, imports unset preferences and preserves old paths.
    public static func run(
        home: String = NSHomeDirectory(),
        defaults: UserDefaults = .standard,
        domain: String = "com.mikemcquaid.Sanductor",
        legacyDomain: String = "com.mikemcquaid.AgentIDE",
    ) throws {
        guard isNeeded(defaults: defaults) else {
            return
        }

        let manager = FileManager.default
        for (old, new) in [
            (home + "/.agentide", home + "/.sanductor"),
            (home + "/Library/Application Support/AgentIDE", home + "/Library/Application Support/Sanductor"),
        ] {
            if try attributes(old)?[.type] as? FileAttributeType == .typeSymbolicLink {
                guard old == home + "/.agentide",
                      try manager.destinationOfSymbolicLink(atPath: old) == ".sanductor"
                else {
                    throw SessionServiceError("Cannot migrate a linked directory: " + old)
                }
            } else {
                try copyMissing(from: old, to: new)
            }
        }
        if try attributes(home + "/.agentide")?[.type] as? FileAttributeType == .typeDirectory {
            try manager.moveItem(
                atPath: home + "/.agentide", toPath: home + "/.sanductor/.agentide-backup-" + UUID().uuidString,
            )
        }
        if try attributes(home + "/.agentide") == nil, manager.fileExists(atPath: home + "/.sanductor") {
            try manager.createSymbolicLink(atPath: home + "/.agentide", withDestinationPath: ".sanductor")
        }
        var preferences = defaults.persistentDomain(forName: domain) ?? [:]
        preferences.merge(defaults.persistentDomain(forName: legacyDomain) ?? [:]) { current, _ in current }
        preferences[completedKey] = true
        defaults.setPersistentDomain(preferences, forName: domain)
    }

    // MARK: Private

    private static let completedKey = "agentideMigrationComplete"

    // An absent path must remain distinct from an existing destination.
    // swiftlint:disable:next discouraged_optional_collection
    private static func attributes(_ path: String) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private static func copyMissing(from source: String, to destination: String) throws {
        let manager = FileManager.default
        guard let sourceAttributes = try attributes(source) else {
            return
        }

        let destinationAttributes = try attributes(destination)
        if sourceAttributes[.type] as? FileAttributeType == .typeDirectory {
            if let destinationAttributes {
                guard destinationAttributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw SessionServiceError("Cannot migrate into a non-directory: " + destination)
                }
            } else {
                try manager.createDirectory(atPath: destination, withIntermediateDirectories: true)
            }
            for name in try manager.contentsOfDirectory(atPath: source) {
                try copyMissing(from: source + "/" + name, to: destination + "/" + name)
            }
        } else if destinationAttributes == nil {
            let temporary = destination + ".migration-" + UUID().uuidString
            defer { try? manager.removeItem(atPath: temporary) }
            try manager.copyItem(atPath: source, toPath: temporary)
            try manager.moveItem(atPath: temporary, toPath: destination)
        }
    }
}
