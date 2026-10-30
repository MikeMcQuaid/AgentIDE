import Foundation

// MARK: - SidebarTarget

/// A worktree's captured identity, shared with the phone without host metadata.
public struct SidebarTarget: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(repository: String, repositoryPath: String, branch: String, path: String) {
        self.repository = repository
        self.repositoryPath = repositoryPath
        self.branch = branch
        self.path = path
    }

    public init(_ worktree: Worktree) {
        self.init(
            repository: worktree.repositoryName,
            repositoryPath: worktree.repositoryPath,
            branch: worktree.branch,
            path: worktree.path,
        )
    }

    // MARK: Public

    public let repository: String
    public let repositoryPath: String
    public let branch: String
    public let path: String

    public var id: String {
        path
    }

    public var label: String {
        repository + ": " + branch
    }
}

// MARK: - BlockDependency

/// One reason work cannot proceed, retained until explicitly resolved.
public enum BlockDependency: Codable, Hashable, Sendable {
    case note(String)
    case worktree(SidebarTarget)
    case issue(repositoryPath: String, number: Int, title: String)
    case pullRequest(repositoryPath: String, number: Int, title: String)

    // MARK: Public

    public var label: String {
        switch self {
        case let .note(text):
            text

        case let .worktree(target):
            target.label

        case let .issue(_, number, title):
            "Issue #" + String(number) + ": " + title

        case let .pullRequest(_, number, title):
            "PR #" + String(number) + ": " + title
        }
    }
}

// MARK: - WorkBlock

/// A manual status override, owned by host metadata.
public struct WorkBlock: Codable, Hashable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(target: SidebarTarget, scope: Scope, dependency: BlockDependency, createdAt: Date = Date()) {
        self.target = target
        self.scope = scope
        self.dependency = dependency
        // Metadata uses ISO 8601 seconds; keep identity stable across a restart.
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }

    // MARK: Public

    public enum Scope: String, CaseIterable, Codable, Sendable {
        case worktree = "Worktree"
        case branch = "Branch"
    }

    public static let maximumNoteBytes = 2_000

    public let target: SidebarTarget
    public let scope: Scope
    public let dependency: BlockDependency
    public let createdAt: Date

    public var id: String {
        if scope == .worktree {
            "worktree#" + target.path
        } else {
            "branch#" + target.repositoryPath + "#" + target.branch
        }
    }

    public func applies(to target: SidebarTarget) -> Bool {
        if scope == .worktree {
            self.target.path == target.path
        } else {
            self.target.repositoryPath == target.repositoryPath && self.target.branch == target.branch
        }
    }
}
