import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The branch a new session starts from: the default branch, or a
/// local branch to stack on. Worktree branches come from memory first.
struct BaseBranchPicker: View {
    // MARK: Internal

    let model: DashboardModel
    let repository: Repository?
    /// Why no base can be picked right now, which disables the picker.
    let unavailableReason: String?

    @Binding var selection: String?

    var body: some View {
        let group = model.groups.first { $0.repository.path == repository?.path }
        let worktreeBranches = Self.worktreeBranches(in: group, listed: branches)
        Picker("Base branch", selection: $selection) {
            Label(group?.defaultBranch ?? "Default branch", image: "octicon-git-branch")
                .tag(String?.none)
            if worktreeBranches.isEmpty == false {
                Section("Worktrees") {
                    ForEach(worktreeBranches, id: \.self) { branch in
                        Label(branch, image: "octicon-git-branch").tag(String?.some(branch))
                    }
                }
            }
            if let branches {
                let held = Set(worktreeBranches)
                let otherBranches = branches.filter { held.contains($0) == false }
                if otherBranches.isEmpty == false {
                    Section("Other branches") {
                        ForEach(otherBranches, id: \.self) { branch in
                            Label(branch, image: "octicon-git-branch").tag(String?.some(branch))
                        }
                    }
                }
                // A preset git does not list (a detached worktree
                // names its directory) stays visible and is refused
                // at launch, rather than quietly becoming the default.
                if let selection, branches.contains(selection) == false {
                    Label(selection + " (no such branch)", systemImage: "exclamationmark.triangle")
                        .tag(String?.some(selection))
                }
            } else if repository != nil {
                Text("Listing branches…").selectionDisabled()
            }
        }
        .labelsHidden()
        .font(nameStyle.font)
        .fixedSize()
        .disabled(unavailableReason != nil)
        .hoverHelp(unavailableReason ?? "The branch the new session starts from")
        .task(id: repository?.id ?? "") { await reload() }
    }

    // MARK: Private

    // Every local branch git lists, nil until it answers.
    // swiftlint:disable:next discouraged_optional_collection
    @State private var branches: [String]?

    private var nameStyle: NameStyle = .init()

    /// Branches other worktrees hold, limited once listed to real
    /// branches (a worktree mid-rebase reports its directory name).
    private static func worktreeBranches(
        in group: RepositoryGroup?,
        listed: [String]?, // swiftlint:disable:this discouraged_optional_collection
    ) -> [String] {
        let held = (group?.items ?? [])
            .filter { $0.isPlaceholder == false }
            .map(\.worktree)
            .filter { $0.path != $0.repositoryPath && $0.isHostDirectory == false && $0.branch != group?.defaultBranch }
            .map(\.branch)
        guard let listed else {
            return held
        }

        let real = Set(listed)
        return held.filter(real.contains)
    }

    private func reload() async {
        branches = nil
        guard let repository else {
            return
        }

        let fresh = await model.baseBranches(repository: repository)
        guard Task.isCancelled == false else {
            return
        }

        branches = fresh
    }
}
