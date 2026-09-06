import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// The footer's copy buttons: what a click takes to the
/// clipboard, said in a word and, when there is any of it, the
/// app's own copy symbol and a count, in the run the sidebar's
/// arrows use. Split from the footer for length.
extension PullRequestFooterView {
    /// The copy actions for the open conversation, in the footer's
    /// click-order run.
    @ViewBuilder
    func copyButtons(for selected: PullRequestSummary) -> some View {
        // The word says what, the glyph that a click copies it and
        // the count how much there is; none of it dims the button
        // to the word alone, which is the same fact the count
        // would have reported.
        BusyButton(
            label: Self.copyLabel("Reviews", count: selected.unresolvedComments),
            accessibilityLabel: Self.copyTitle("Reviews", count: selected.unresolvedComments),
            busy: "Copying",
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
            label: Self.copyLabel("Failures", count: selected.failingCheckLinks.count),
            accessibilityLabel: Self.copyTitle("Failures", count: selected.failingCheckLinks.count),
            busy: "Copying",
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

    /// The symbol every copy in the app carries, drawn inline at the
    /// text's own size between the word and the count, where
    /// `Push ↑9` puts its arrow: a character that looked like it did
    /// not look like it.
    static let copyIcon = "doc.on.doc"

    /// A copy button's label: what it copies and, when there is
    /// any, the symbol and the count. Nothing to copy is the word
    /// alone, greyed out.
    static func copyLabel(_ name: String, count: Int) -> Text {
        guard count > 0 else {
            return Text(name)
        }

        return Text(name + " ") + Text(Image(systemName: copyIcon)) + Text(String(count))
    }

    /// The same as VoiceOver reads it.
    static func copyTitle(_ name: String, count: Int) -> String {
        if count > 0 {
            name + " " + String(count)
        } else {
            name
        }
    }
}
