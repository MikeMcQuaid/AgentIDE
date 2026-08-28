/// A branch's unfinished pull request text, kept so leaving the tab
/// and coming back does not lose the writing.
public struct PullRequestFormDraft: Codable, Sendable {
    // MARK: Lifecycle

    /// Creates a draft.
    public init(title: String, body: String, template: String) {
        self.title = title
        self.body = body
        self.template = template
    }

    // MARK: Public

    /// The drafted title.
    public let title: String

    /// The drafted body.
    public let body: String

    /// The template as edited.
    public let template: String
}
