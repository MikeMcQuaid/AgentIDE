import AgentIDEDomain

extension AutofixCoordinator {
    func resolveMarked(
        state: PullRequestAutomation,
        head: String,
        context: AutofixContext,
    ) async throws {
        let key = context.key
        let store = context.store
        let driver = context.driver
        guard state.resolutions.isEmpty == false else {
            return
        }

        let cached = try await driver.threads(state, false)
        let changed = cached.contains { thread in
            state.resolutions[thread.resolveID].map { mark in
                thread.isResolved || thread.comments.last?.id != mark.commentID
            } ?? false
        }
        let threads = changed ? try await driver.threads(state, true) : cached
        for (id, mark) in state.resolutions {
            guard let thread = threads.first(where: { $0.resolveID == id }) else {
                continue
            }

            if thread.isResolved || thread.comments.last?.id != mark.commentID {
                try store.updatePersisting { value in
                    value.pullRequestAutomation[key]?.resolutions[id] = nil
                    value.pullRequestAutomation[key]?.lastResult = thread.isResolved
                        ? "Conversation resolved" : "New comments arrived; the conversation was left open"
                }
                continue
            }
            guard mark.requested == false, head != mark.head,
                  let fresh = try await driver.summary(state, true), fresh.url == state.url,
                  fresh.state == "OPEN", fresh.headCommit != nil, fresh.headCommit != mark.head,
                  let checked = try await driver.threads(state, true).first(where: { $0.resolveID == id }),
                  checked.isResolved == false, checked.comments.last?.id == mark.commentID
            else {
                continue
            }

            var claimed = false
            try store.updatePersisting { metadata in
                guard metadata.pullRequestAutomation[key]?.resolutions[id] == mark else {
                    return
                }

                metadata.pullRequestAutomation[key]?.resolutions[id]?.requested = true
                claimed = true
            }
            guard claimed else {
                continue
            }

            await resolve(id, state: state, context: context)
        }
    }

    func resolve(_ id: String, state: PullRequestAutomation, context: AutofixContext) async {
        let key = context.key
        let store = context.store
        let driver = context.driver
        do {
            try await driver.resolve(state, id)
            try store.updatePersisting { value in
                value.pullRequestAutomation[key]?.resolutions[id] = nil
                value.pullRequestAutomation[key]?.lastResult = "Resolved a marked conversation after the push"
            }
        } catch {
            store.update { value in
                value.pullRequestAutomation[key]?.lastResult = "Resolution unconfirmed; mark again to retry. "
                    + error.localizedDescription
            }
        }
    }
}
