// MARK: - NewPullRequest

/// What a pull request opens with, apart from where: the form's
/// title, its body with the template appended, and the labels
/// picked from the repository's own.
public struct NewPullRequest: Sendable {
    // MARK: Lifecycle

    /// Creates the request.
    public init(title: String, body: String, labels: [String], isDraft: Bool = false) {
        self.title = title
        self.body = body
        self.labels = labels
        self.isDraft = isDraft
    }

    // MARK: Public

    /// The title.
    public let title: String

    /// The body.
    public let body: String

    /// The labels to attach.
    public let labels: [String]

    /// Whether it opens as a draft: work to read rather than work
    /// to merge, which is what an agent's first attempt usually is.
    public let isDraft: Bool
}
