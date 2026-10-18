import Foundation

// MARK: - HerdrSnapshot

/// The public herdr snapshot shared by local and SSH clients.
public struct HerdrSnapshot: Decodable, Sendable {
    public struct Workspace: Decodable, Sendable {
        // MARK: Public

        public let workspaceID: String
        public let label: String

        // MARK: Private

        // Keep wire keys beside their record; SwiftFormat removes matching raw values.
        // swiftlint:disable explicit_enum_raw_value
        // swiftlint:disable:next nesting
        private enum CodingKeys: String, CodingKey {
            case workspaceID = "workspace_id"
            case label
        }
        // swiftlint:enable explicit_enum_raw_value
    }

    public struct Pane: Decodable, Sendable {
        // MARK: Public

        public let paneID: String
        public let workspaceID: String
        public let cwd: String?
        public let foregroundCwd: String?
        public let agent: String?
        public let agentStatus: String?

        /// The directory Git can inspect without interpreting a session label.
        public var directory: String? {
            foregroundCwd.flatMap { $0.isEmpty ? nil : $0 } ?? cwd.flatMap { $0.isEmpty ? nil : $0 }
        }

        // MARK: Private

        // Keep wire keys beside their record; SwiftFormat removes matching raw values.
        // swiftlint:disable explicit_enum_raw_value
        // swiftlint:disable:next nesting
        private enum CodingKeys: String, CodingKey {
            case paneID = "pane_id"
            case workspaceID = "workspace_id"
            case cwd
            case foregroundCwd = "foreground_cwd"
            case agent
            case agentStatus = "agent_status"
        }
        // swiftlint:enable explicit_enum_raw_value
    }

    public let workspaces: [Workspace]
    public let panes: [Pane]

    public static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(HerdrSnapshotEnvelope.self, from: data).result.snapshot
    }
}

// MARK: - HerdrSnapshotEnvelope

private struct HerdrSnapshotEnvelope: Decodable {
    let result: HerdrSnapshotResult
}

// MARK: - HerdrSnapshotResult

private struct HerdrSnapshotResult: Decodable {
    let snapshot: HerdrSnapshot
}
