extension AutofixCoordinator {
    func ready(_ target: AutofixDriver.Target, head: String, context: AutofixContext) async -> Bool {
        guard let reason = await context.driver.waitReason(target, head) else {
            return true
        }

        context.store.update { $0.pullRequestAutomation[context.key]?.pending = reason }
        return false
    }

    func deliver(_ attempt: AutofixAttempt, prompt: String, context: AutofixContext) async {
        do {
            try await context.driver.deliver(attempt, prompt)
            context.store.update { value in
                guard value.pullRequestAutomation[context.key]?.attempt?.id == attempt.id else {
                    return
                }

                value.pullRequestAutomation[context.key]?.pending = attempt.commitRequestedHead == nil
                    ? "Fix-and-commit prompt sent; follow progress in the agent pane"
                    : "Commit-only prompt sent; waiting for the agent to commit existing fixes"
            }
        } catch {
            context.store.update { value in
                value.pullRequestAutomation[context.key]?.lastResult = "Delivery unconfirmed; it will not be repeated. "
                    + error.localizedDescription
            }
        }
    }
}
