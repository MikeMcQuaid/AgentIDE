extension AutofixAttempt {
    /// Keeps older delivery claims without requiring later default fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sources = try container.decode(Set<Kind>.self, forKey: .sources)
        head = try container.decode(String.self, forKey: .head)
        remoteHead = try container.decodeIfPresent(String.self, forKey: .remoteHead) ?? head
        localThreadIDs = try container.decodeIfPresent(Set<String>.self, forKey: .localThreadIDs) ?? []
        branch = try container.decode(String.self, forKey: .branch)
        worktreePath = try container.decode(String.self, forKey: .worktreePath)
        sessionName = try container.decode(String.self, forKey: .sessionName)
        paneID = try container.decode(String.self, forKey: .paneID)
        threads = try container.decodeIfPresent([String: PendingThreadResolution].self, forKey: .threads) ?? [:]
        commitRequestedHead = try container.decodeIfPresent(String.self, forKey: .commitRequestedHead)
        hasObservedTurn = try container.decodeIfPresent(Bool.self, forKey: .hasObservedTurn)
        rebase = try container.decodeIfPresent(AutofixRebase.self, forKey: .rebase)
    }

    // Coding keys match the existing synthesised spelling.
    // swiftlint:disable explicit_enum_raw_value
    enum CodingKeys: String, CodingKey {
        case id
        case sources
        case head
        case remoteHead
        case localThreadIDs
        case branch
        case worktreePath
        case sessionName
        case paneID
        case threads
        case commitRequestedHead
        case hasObservedTurn
        case rebase
    }
    // swiftlint:enable explicit_enum_raw_value
}
