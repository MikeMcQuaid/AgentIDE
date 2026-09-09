import SwiftUI
import TerminalUI

/// The footer's actions when the entry on screen is stacked work:
/// the same titles in the same places as a lone branch's, doing the
/// stack's version of each. Split from the footer for length.
extension PullRequestFooterView {
    /// The branch actions: a stacked entry's buttons stand where a
    /// lone branch's buttons do, so the flow does not move about. Rebase is the
    /// stack's from any layer, its bottom included, since rebasing
    /// one layer alone is what loses the layers above it.
    @ViewBuilder var branchActions: some View {
        if model.isInStack {
            restackButton
        } else {
            rebaseButton
        }
        if model.isStackedEntry {
            pushStackButton
        } else {
            pushButton
        }
    }

    /// A stack's own pair of buttons, in the place and dress of the
    /// branch pair it stands in for: the same titles through
    /// `actionTitle`, the same order, the same counts and the same
    /// past tense while dim, doing the stack's version of the work.
    private var restackButton: some View {
        BusyButton(
            actionTitle(
                stackSignsOnly ? "Sign" : "Rebase",
                arrow: Self.downArrow,
                count: stackSignsOnly ? "" : rebaseCount,
                active: model.canRestack,
                done: model.rebaseDoneTitle,
            ),
            busy: stackSignsOnly ? "Signing" : "Rebasing",
            disabled: model.canRestack == false,
        ) {
            if await model.restack() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(
            model.canRestack
                ? "Fetch, then rebase every branch onto the one below it, signing every commit it "
                + "replays and leaving alone any branch already in place and signed, then push back "
                + "every branch the remote already has, since GitHub reads a moved stack as no stack "
                + "until then; a conflict aborts and reports to Messages"
                : "Every branch is already on the one below it, with its tip signed",
            shortcut: "⌥⌘R",
        )
    }

    /// Whether the stack's rebase would only sign: every branch is
    /// on the one below it and a tip is unsigned.
    private var stackSignsOnly: Bool {
        model.stacking.needsRestack == false
    }

    private var pushStackButton: some View {
        BusyButton(
            actionTitle(
                "Push",
                arrow: Self.upArrow,
                count: stackPushCount,
                active: model.canPushStack,
                done: model.pushDoneTitle,
            ),
            busy: "Pushing",
            disabled: model.canPushStack == false,
        ) {
            if await model.pushStack() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(model.pushStackHelp)
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
    /// under another pull request's name. Queue where the repository
    /// merges through a queue and Merge otherwise, as the lone
    /// button says it, and dim until GitHub knows the stack.
    @ViewBuilder var mergeStackButton: some View {
        if model.selected?.state == "OPEN" {
            BusyButton(
                model.hasMergeQueue ? "Queue" : "Merge",
                busy: model.hasMergeQueue ? "Queueing" : "Merging",
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
