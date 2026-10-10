import AgentIDEData
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
        let count = reviewCount(for: selected)
        // The word says what, the glyph that a click copies it and
        // the count how much there is; none of it dims the button
        // to the word alone, which is the same fact the count
        // would have reported.
        BusyButton(
            label: copyLabel("Reviews", count: count),
            accessibilityLabel: Self.copyTitle("Reviews", count: count),
            busy: "Copying",
            disabled: count == 0,
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
        .hoverHelp("Copy unresolved local AI and GitHub conversations; Cmd-click opens GitHub reviews "
            + "in your browser, Shift-click in the Browser tab; dimmed while none is unresolved")
        // One button for the failing checks: a click copies their
        // logs, and a modifier opens them instead, since the
        // modifier is read at the click and `LinkOpener` already
        // sends Cmd to the browser and anything else to the tab.
        // Dimmed until the rollup is red with runs to read: pending
        // and green have no failed log, and a red rollup whose
        // failures are not Actions runs has none either.
        BusyButton(
            label: copyLabel("Checks", count: selected.failingCheckLinks.count),
            accessibilityLabel: Self.copyTitle("Checks", count: selected.failingCheckLinks.count),
            busy: "Copying",
            disabled: selected.hasFailingChecks == false || selected.failingCheckLinks.isEmpty,
        ) {
            if NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) == false {
                model.openFailingChecks(selected)
            } else if await model.copyFailingLogs(selected) == false {
                utilityTab = UtilityTabTarget.errors
            }
        }
        .hoverHelp("Copy the head and tail of every failing Actions run's log, the first "
            + String(CheckLog.logHeadLines) + " lines and the last "
            + String(CheckLog.logTailLines) + " with the bytes of each end capped, a run still "
            + "in progress answering with its already-failed jobs; Cmd-click opens the failing check in "
            + "your browser, Shift-click in the Browser tab; dimmed until a check fails")
    }

    /// Explicit manual copies retain their broader scope beside filtered feedback.
    func rawFeedbackMenu(for selected: PullRequestSummary) -> some View {
        Menu("Copy unfiltered feedback") {
            Button("All unresolved reviews") { Task { await model.copyUnresolvedComments(selected) } }
                .disabled(reviewCount(for: selected) == 0)
            Button("Failing CI logs") {
                Task {
                    if await model.copyFailingLogs(selected) == false {
                        utilityTab = UtilityTabTarget.errors
                    }
                }
            }
            .disabled(selected.hasFailingChecks == false || selected.failingCheckLinks.isEmpty)
        }
    }

    /// The symbol every copy in the app carries, drawn inline at the
    /// text's own size between the word and the count, where
    /// `Push ↑9` puts its arrow: a character that looked like it did
    /// not look like it.
    static let copyIcon = "doc.on.doc"

    private func reviewCount(for summary: PullRequestSummary) -> Int {
        _ = reviewGeneration
        return model.reviewCount(for: summary)
    }

    /// A copy button's label: what it copies and, when there is
    /// any, the symbol and the count. Nothing to copy is the word
    /// alone, greyed out.
    func copyLabel(_ name: String, count: Int) -> Text {
        guard count > 0 else {
            return Text(name)
        }

        let icon = Text(Image(systemName: Self.copyIcon)).font(interfaceStyle.systemFont(ofSize: Self.copyIconSize))
        return Text("\(name) \(icon)\(String(count))")
    }

    /// The symbol's size: the label's own is thirteen points, and
    /// a symbol drawn at that overhung the digits beside it; about
    /// a third smaller sits on the baseline with them.
    private static let copyIconSize: CGFloat = 9

    /// The same as VoiceOver reads it.
    static func copyTitle(_ name: String, count: Int) -> String {
        if count > 0 {
            name + " " + String(count)
        } else {
            name
        }
    }
}
