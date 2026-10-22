import SwiftUI
import TerminalUI

/// The same preparation and push button for a branch or a stack.
extension PullRequestFooterView {
    var branchActions: some View {
        BusyButton(
            actionTitle(
                model.publishTitle,
                arrow: Self.upArrow,
                count: pushCount,
                active: model.canPublish,
                done: model.pushDoneTitle,
            ),
            busy: "Preparing and Pushing",
            disabled: model.canPublish == false,
        ) {
            if await model.publish() == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp(model.publishHelp, shortcut: "⇧⌘P")
    }

    private var pushCount: String {
        let count = model.isInStack ? model.unpushedStackBranches.count : model.commitsAboveBase
        return count > 0 ? String(count) : ""
    }
}
