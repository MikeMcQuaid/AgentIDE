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
        // No Push beside a live Rebase and Push: two buttons for one
        // job, and the second pressed first pushed branches about to
        // be moved.
        if model.isInStack, model.canRestack {
            EmptyView()
        } else if model.isStackedEntry {
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
            restackTitle,
            busy: (stackSignsOnly ? "Signing" : "Rebasing") + " and Pushing",
            disabled: model.canRestack == false,
        ) {
            if await model.restack() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(
            model.canRestack
                ? "Fetch, then rebase every branch onto the one below it, signing every commit it "
                + "replays and leaving alone any branch already in place and signed, then push the whole "
                + "stack bottom first, publishing any branch nobody has pushed yet; a conflict aborts and "
                + "reports to Messages"
                : model.stack.stackingBlocker ?? "Every branch is already on the one below it, with its tip signed",
            shortcut: "⌥⌘R",
        )
    }

    /// Whether the stack's rebase would only sign: every branch is
    /// on the one below it and a tip is unsigned.
    private var stackSignsOnly: Bool {
        model.stacking.needsRestack == false
    }

    /// The rebase's title with the push it ends in: the branch pair's
    /// shape for each half, what comes down and what goes up.
    private var restackTitle: String {
        let title = actionTitle(
            stackSignsOnly ? "Sign" : "Rebase",
            arrow: Self.downArrow,
            count: stackSignsOnly ? "" : rebaseCount,
            active: model.canRestack,
            done: model.rebaseDoneTitle,
        )
        guard model.canRestack else {
            return title
        }

        return title + " and Push" + (stackPushCount.isEmpty ? "" : " " + Self.upArrow + stackPushCount)
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

    /// The same, for a stack: how many of its branches the remote
    /// lacks, since a stack pushes by branch rather than by commit.
    private var stackPushCount: String {
        let branches = model.stacking.unpushedBranches.count
        return branches > 0 ? String(branches) : ""
    }
}
