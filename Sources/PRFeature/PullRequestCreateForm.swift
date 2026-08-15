import SwiftUI
import TerminalUI

/// The pull request creation form, shown in place of the list when
/// the branch has no open pull request: title, body and the
/// repository's template in three fields, with the template appended
/// below the body when the pull request opens.
struct PullRequestCreateForm: View {
    // MARK: Internal

    @Bindable var model: PullRequestsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("No open pull request for this branch")
                .font(.subheadline.weight(.semibold))
            TextField("Title", text: $model.prTitle)
                .textFieldStyle(.roundedBorder)
                .hoverHelp("The pull request title; git convention keeps it short and imperative")
            Text("Body").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.prBody)
                .font(.body)
                .frame(minHeight: Self.bodyMinimumHeight)
                .border(.separator)
                .hoverHelp("The description in your own words; the template below is appended after it")
            Text("Template").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.prTemplate)
                .font(.body.monospaced())
                .frame(minHeight: Self.templateMinimumHeight)
                .border(.separator)
                .hoverHelp("The repository's pull request template, editable; appended below the body")
            actionsRow
        }
        .padding(Self.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let bodyMinimumHeight: CGFloat = 120
    private static let templateMinimumHeight: CGFloat = 160

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage("utilityTab")
    private var utilityTab = ""

    /// Generate on the left, Open PR on the right.
    private var actionsRow: some View {
        HStack {
            BusyButton(
                "",
                busy: "Generating",
                systemImage: "sparkles",
                disabled: model.prTitle.isEmpty == false && model.prBody.isEmpty == false,
            ) {
                if await model.generateDescription() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            }
            .hoverHelp(
                "Fill the blank fields from the branch's commits: one commit's own message "
                    + "directly, several summarised by the on-device model",
            )
            Spacer()
            BusyButton("Open PR", busy: "Opening", disabled: model.prTitle.isEmpty) {
                if await model.createPullRequest() == false {
                    utilityTab = UtilityTabTarget.errors
                }
            }
            .hoverHelp("Push if needed, then open the pull request with this title and body")
        }
    }
}
