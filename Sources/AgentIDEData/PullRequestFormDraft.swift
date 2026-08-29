/// A branch's unfinished pull request text, kept so leaving the tab
/// and coming back does not lose the writing.
public struct PullRequestFormDraft: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a draft.
    public init(title: String, body: String, template: String, labels: [String] = []) {
        self.title = title
        self.body = body
        self.template = template
        self.labels = labels
    }

    /// Drafts saved before labels existed have no key for them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        template = try container.decode(String.self, forKey: .template)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
    }

    // MARK: Public

    /// The drafted title.
    public let title: String

    /// The drafted body.
    public let body: String

    /// The template as edited.
    public let template: String

    /// The labels picked for the pull request.
    public let labels: [String]
}
