import Foundation

/// The scope each worktree was last reviewed in, remembered so
/// moving between worktrees comes back to the view each one had.
extension ReviewModel {
    /// The stored scope for a worktree, the last commit until one is
    /// chosen.
    static func rememberedScope(for worktreePath: String) -> Scope {
        UserDefaults.standard
            .string(forKey: scopeKey + worktreePath)
            .flatMap(Scope.init(storageName:)) ?? .lastCommit
    }

    func remember(_ scope: Scope) {
        UserDefaults.standard.set(scope.storageName, forKey: Self.scopeKey + worktreePath)
    }

    private static let scopeKey = "reviewScope#"
}

extension ReviewModel.Scope {
    /// Stored names, kept apart from the case names so a rename
    /// never loses what was chosen.
    var storageName: String {
        switch self {
        case .uncommitted:
            "uncommitted"

        case .lastCommit:
            "lastCommit"

        case .upstream:
            "upstream"

        case .branch:
            "branch"
        }
    }

    init?(storageName: String) {
        switch storageName {
        case "uncommitted":
            self = .uncommitted

        case "lastCommit":
            self = .lastCommit

        case "upstream":
            self = .upstream

        case "branch":
            self = .branch

        default:
            return nil
        }
    }
}
