import SwiftUI
import TerminalUI

/// The footer's actions when the entry on screen is stacked work:
/// the same icons in the same places as a lone branch's, doing the
/// stack's version of each. Split from the footer for length.
extension PullRequestFooterView {
    /// The branch actions: a stacked entry's stand where a lone
    /// branch's do, so the flow does not move about.
    @ViewBuilder var branchActions: some View {
        if model.isStackedEntry {
            restackButton
            pushStackButton
        } else {
            rebaseButton
            pushButton
        }
    }

    /// A stack's own pair, in the place and dress of the branch
    /// pair they stand in for: the same icons, the same order, the
    /// same counts, doing the stack's version of the work. Both dim
    /// when there is nothing to do.
    private var restackButton: some View {
        BusyButton(
            rebaseCount,
            busy: "Rebasing",
            systemImage: "arrow.triangle.2.circlepath",
            accessibilityLabel: "Restack",
            disabled: model.canRestack == false,
        ) {
            await model.restack()
        }
        .hoverHelp(
            model.canRestack
                ? "Rebase every branch onto the one below it, signed, leaving alone any already there"
                : "Every branch is already on the one below it",
        )
    }

    private var pushStackButton: some View {
        BusyButton(
            stackPushCount,
            busy: "Pushing",
            systemImage: "arrow.up",
            accessibilityLabel: "Push stack",
            disabled: model.canPushStack == false,
            keepsTitle: true,
        ) {
            await model.pushStack()
        }
        .hoverHelp(
            model.canPushStack
                ? "Push every branch of the stack, bottom first"
                : "Every branch of the stack is already pushed",
        )
    }

    /// Why the stacked merge is in its current state: what it does
    /// when it can, and what it is waiting for when it cannot.
    private var mergeStackHelp: String {
        guard model.isStackLinked else {
            return "The pull requests below this one are not all open, so there is no stack to "
                + "merge and this branch must not be merged into its base on its own"
        }
        guard model.isStackBelowReady else {
            return "A stack merges all at once, and a pull request below this one is not ready: "
                + "it is in conflict, its checks have not passed, or a review it needs is missing"
        }

        return "Stack these pull requests on GitHub if they are not already, then merge, queue or "
            + "automerge this one and every one below it, in order, as the repository allows"
    }

    /// The same, for a stack: how many of its branches the remote
    /// lacks, since a stack pushes by branch rather than by commit.
    private var stackPushCount: String {
        let branches = model.stacking.unpushedBranches.count
        return branches > 0 ? String(branches) : ""
    }

    /// A stacked entry merges with everything under it or not at
    /// all: merging one out of order would land its parent's commits
    /// under another pull request's name. One word, since which of
    /// merge, queue or automerge happens is the repository's
    /// business rather than this button's, and dim until GitHub
    /// knows the stack.
    @ViewBuilder var mergeStackButton: some View {
        if model.selected?.state == "OPEN" {
            BusyButton(
                "Merge",
                busy: "Merging",
                prominent: true,
                disabled: model.canMergeStack == false,
            ) {
                if await model.mergeStack() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            }
            .hoverHelp(mergeStackHelp)
        }
    }
}
