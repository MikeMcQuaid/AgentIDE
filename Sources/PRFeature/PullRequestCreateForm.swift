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
                .disabled(isGenerating)
                .overlay(alignment: .trailing) { generateButton.padding(.trailing, Self.overlayPadding) }
                .hoverHelp("The pull request title; git convention keeps it short and imperative")
            Text("Body").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.prBody)
                .font(.body)
                .frame(minHeight: Self.bodyMinimumHeight)
                .border(.separator)
                .disabled(isGenerating)
                .hoverHelp("The description in your own words; the template below is appended after it")
            templateSection
        }
        .padding(Self.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    private static let overlayPadding: CGFloat = 4

    private static let bodyMinimumHeight: CGFloat = 120
    private static let templateMinimumHeight: CGFloat = 160

    /// Drafting locks every field, so a slow model never races
    /// typing it would then overwrite.
    @State private var isGenerating = false

    /// The cross-module signal that switches the utility pane's tab.
    @AppStorage(UtilityTabTarget.key)
    private var utilityTab = ""

    /// The repository's template with its tick-all shortcut.
    @ViewBuilder private var templateSection: some View {
        if model.hasTemplate {
            HStack {
                Text("Template").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.hasAIDisclosure {
                    Button("Disclose AI", systemImage: "sparkles.rectangle.stack") {
                        model.insertAIDisclosure()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isGenerating)
                    .hoverHelp(
                        "Name the harness and model that wrote this branch, and that you reviewed and "
                            + "tested it, in the template's AI section",
                    )
                }
                Button("Tick every box", systemImage: "checklist") { model.tickTemplateBoxes() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isGenerating || model.prTemplate.contains("[ ]") == false)
                    .hoverHelp("Tick every unticked checkbox in the template")
            }
            TextEditor(text: $model.prTemplate)
                .font(.body.monospaced())
                .frame(minHeight: Self.templateMinimumHeight)
                .border(.separator)
                .disabled(isGenerating)
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
