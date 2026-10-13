/// Where a session's prompt comes from; split from the form's file
/// for length.
extension AgentSessionForm {
    enum PromptSource: CaseIterable {
        case prompt
        case issue
        case pullRequest
        case advisory

        // MARK: Internal

        var title: String {
            switch self {
            case .prompt:
                "Prompt"

            case .issue:
                "Issue"

            case .pullRequest:
                "PR"

            case .advisory:
                "Advisory"
            }
        }
    }
}
