import SwiftUI

/// The same copy action wherever a pull request is shown.
public struct CopyPullRequestURLButton: View {
    // MARK: Lifecycle

    public init(_ url: String) {
        self.url = url
    }

    // MARK: Public

    public var body: some View {
        Button("Copy pull request URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }

    // MARK: Private

    private let url: String
}
