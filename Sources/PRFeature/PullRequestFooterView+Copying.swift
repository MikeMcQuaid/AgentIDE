import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// The footer's copy buttons: what a click takes to the
/// clipboard, said in a word, a count and the glyph every copy
/// in the app carries. Split from the footer for length.
extension PullRequestFooterView {
    /// The copy actions for the open conversation, in the footer's
    /// click-order run.
    @ViewBuilder
    func copyButtons(for selected: PullRequestSummary) -> some View {
        // The glyph says a click copies, the word says what, and
        // the count how much of it there is; none of it dims the
        // button, which is the same fact the count reports.
        BusyButton(
            Self.copyLabel("Reviews", count: selected.unresolvedComments),
            busy: "Copying",
            systemImage: Self.copyIcon,
            disabled: selected.unresolvedComments == 0,
        ) {
            // Both buttons read the modifier at the click, as
            // `LinkOpener` does: Cmd goes to the browser, Shift to
            // the Browser tab, a plain click to the clipboard.
            if NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) == false {
                model.openReviews(selected)
            } else {
                await model.copyUnresolvedComments(selected)
            }
        }
        .hoverHelp("Copy every unresolved review conversation to the clipboard; Cmd-click opens them "
            + "in your browser, Shift-click in the Browser tab; dimmed while none is unresolved")
        // One button for the failing checks: a click copies their
        // logs, and a modifier opens them instead, since the
        // modifier is read at the click and `LinkOpener` already
        // sends Cmd to the browser and anything else to the tab.
        // Dimmed until the rollup is red with runs to read: pending
        // and green have no failed log, and a red rollup whose
        // failures are not Actions runs has none either.
        BusyButton(
            Self.copyLabel("Failures", count: selected.failingCheckLinks.count),
            busy: "Copying",
            systemImage: Self.copyIcon,
            disabled: selected.hasFailingChecks == false || selected.failingCheckLinks.isEmpty,
        ) {
            if NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) == false {
                model.openFailingChecks(selected)
            } else if await model.copyFailingLogs(selected) == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp("Copy the last " + String(PullRequestsModel.logTailLines)
            + " lines of every failing Actions run's log, a run still in progress answering with its "
            + "already-failed jobs; Cmd-click opens the failing check in your browser, Shift-click "
            + "in the Browser tab; dimmed until a check fails")
    }

    /// The glyph a copy carries everywhere in the app.
    static let copyIcon = "doc.on.doc"

    /// A copy button's label: what it copies and how much of it
    /// there is, a nothing to copy included. The count is always
    /// there, so the button says what it has rather than changing
    /// width as it arrives, and none of it greys the button out.
    static func copyLabel(_ name: String, count: Int) -> String {
        name + " " + String(count)
    }
}
