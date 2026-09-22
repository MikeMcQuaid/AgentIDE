import AgentIDEData

/// Shares each worktree's review across pane and worktree switches.
@preconcurrency
@MainActor
public final class LocalReviewStore {
    // MARK: Lifecycle

    /// Creates the app's shared local reviews using the session service.
    public convenience init(service: SessionService) {
        self.init { LocalReviewModel(service: service, worktreePath: $0) }
    }

    init(makeModel: @escaping (String) -> LocalReviewModel) {
        self.makeModel = makeModel
    }

    deinit {
        // Models live for the app's lifetime.
    }

    // MARK: Internal

    func model(worktreePath: String) -> LocalReviewModel {
        if let model = models[worktreePath] {
            return model
        }

        let model = makeModel(worktreePath)
        models[worktreePath] = model
        return model
    }

    // MARK: Private

    private let makeModel: (String) -> LocalReviewModel
    private var models: [String: LocalReviewModel] = [:]
}
