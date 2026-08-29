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
            HStack {
                Text("No open pull request for this branch")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                generateButton
                resetButton
            }
            if let below = model.unpushedBelow {
                Text("Waiting on `" + below + "` below it to be pushed and opened first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Title", text: $model.prTitle.readOnly(isGenerating || isBlocked))
                .textFieldStyle(.roundedBorder)
                .readOnly(isGenerating || isBlocked)
                .hoverHelp("The pull request title; git convention keeps it short and imperative")
            labelsSection
            Text("Body").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.prBody.readOnly(isGenerating || isBlocked))
                .font(.body)
                .frame(minHeight: Self.bodyMinimumHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.fieldCorner))
                .overlay(RoundedRectangle(cornerRadius: Self.fieldCorner).stroke(.separator))
                .readOnly(isGenerating || isBlocked)
                .hoverHelp("The description in your own words; the template below is appended after it")
            templateSection
        }
        .padding(Self.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private static let fieldCorner: CGFloat = 6
    private static let bodyMinimumHeight: CGFloat = 120
    private static let templateMinimumHeight: CGFloat = 160

    /// Drafting locks every field, so a slow model never races
    /// typing it would then overwrite.
    @State private var isGenerating = false

    /// Whether Reset is asking before throwing typed text away.
    @State private var isConfirmingReset = false

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = ""

    /// Whether a branch below this one is not on the remote yet, a
    /// pull request is opening, or a push or rebase is running:
    /// the fields grey out rather than racing a reload that could
    /// replace what is being typed.
    private var isBlocked: Bool {
        model.unpushedBelow != nil || model.isOpening || model.isBranchActionRunning
    }

    /// Back to what the commits say. Typed text asks first; blank
    /// fields reset without a word.
    private var resetButton: some View {
        Button {
            if Self.hasText(model.prTitle) || Self.hasText(model.prBody) {
                isConfirmingReset = true
            } else {
                Task { await model.resetToCommits() }
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .accessibilityLabel("Reset to the commit message")
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating || isBlocked)
        .hoverHelp("Replace the title and body with what the branch's commits say")
        .confirmationDialog(
            "Replace what you typed with the commit message?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible,
        ) {
            Button("Reset", role: .destructive) { Task { await model.resetToCommits() } }
            Button("Cancel", role: .cancel) { isConfirmingReset = false }
        }
    }

    /// The labels the pull request opens with, once the repository
    /// is known to have any.
    @ViewBuilder private var labelsSection: some View {
        if model.availableLabels.isEmpty == false {
            LabelsRow(
                picked: model.prLabels,
                available: model.availableLabels,
                isEnabled: isGenerating == false && isBlocked == false,
                help: "Labels from the repository to attach when the pull request opens",
            ) { label in
                if model.prLabels.contains(label) {
                    model.prLabels.removeAll { $0 == label }
                } else {
                    model.prLabels.append(label)
                }
            }
        }
    }

    /// The repository's template with its tick-all shortcut.
    @ViewBuilder private var templateSection: some View {
        if model.hasTemplate {
            HStack {
                Text("Template").font(.caption).foregroundStyle(.secondary)
                Spacer()
                // One button, since ticking the AI box and saying
                // what wrote the branch are the same act: the box
                // claims a disclosure and the disclosure answers it.
                Button("Fill template", systemImage: "checklist") { model.tickTemplateBoxes() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isGenerating || model.prTemplate.contains("[ ]") == false)
                    .hoverHelp(
                        "Tick every unticked checkbox, and where the template asks about AI, name the "
                            + "harness and model that wrote this branch and that you reviewed and tested it",
                    )
            }
            TextEditor(text: $model.prTemplate.readOnly(isGenerating || isBlocked))
                .font(.body.monospaced())
                .frame(minHeight: Self.templateMinimumHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.fieldCorner))
                .overlay(RoundedRectangle(cornerRadius: Self.fieldCorner).stroke(.separator))
                .readOnly(isGenerating || isBlocked)
                .hoverHelp("The repository's pull request template, editable; appended below the body")
        }
    }

    /// Sits inside the title field; drafting only ever fills empty
    /// fields, so any typed content dims it.
    private var generateButton: some View {
        Button {
            guard isGenerating == false else {
                return
            }

            isGenerating = true
            // Explicitly main-actor: the continuation after the
            // await must not write view state from elsewhere.
            Task { @MainActor in
                if await model.generateDescription() == false {
                    utilityTab = UtilityTabTarget.errors
                }
                isGenerating = false
            }
        } label: {
            if isGenerating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
                    .accessibilityLabel("Generate title and body")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isGenerating || Self.hasText(model.prTitle) || Self.hasText(model.prBody))
        .hoverHelp(
            "Fill the empty fields from the branch's commits: one commit's own message "
                + "directly, several summarised by the on-device model, and the template "
                + "completed from the commits when the repository has one",
        )
    }

    /// Whether a field holds anything worth keeping; whitespace
    /// alone is as good as empty, and generating replaces it.
    private static func hasText(_ text: String) -> Bool {
        PullRequestsModel.isBlank(text) == false
    }
}
