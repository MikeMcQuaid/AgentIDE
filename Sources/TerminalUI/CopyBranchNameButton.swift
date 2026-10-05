import SwiftUI

/// The same branch copy action in worktrees, stacks and pull requests.
public struct CopyBranchNameButton: View {
    // MARK: Lifecycle

    public init(_ branch: String) {
        self.branch = branch
    }

    // MARK: Public

    public var body: some View {
        Button("Copy branch name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch, forType: .string)
        }
    }

    // MARK: Private

    private let branch: String
}
