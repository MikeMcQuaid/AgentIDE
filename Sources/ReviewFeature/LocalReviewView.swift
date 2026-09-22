import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The editable review brief and the same findings shown beneath the diff.
struct LocalReviewView: View {
    // MARK: Internal

    @Bindable var model: LocalReviewModel

    let diff: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            controls
            promptEditor
            if model.isOutdated {
                Text("The code or review scope changed. Review again before making a fix.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error)
                    .interfaceFont(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Divider()
            if model.isRunning {
                LaunchProgressView("Reviewing changes", waitingOn: model.reviewer.displayName + "'s findings")
            } else if diff.hasLoaded == false {
                LaunchProgressView("Loading review scope", waitingOn: "the selected diff")
            } else {
                findings
                makeFixes
            }
        }
        .padding(Self.spacing)
        .frame(width: Self.width, height: Self.height)
        .onAppear { promptFocused = true }
        .onExitCommand { dismiss() }
        .onChange(of: showsInstructions) { _, shown in promptFocused = shown }
        .onChange(of: model.showsPrompt) { _, shown in
            if shown {
                dismiss()
            }
        }
        .animation(Motion.quick, value: showsInstructions)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let iconSize: CGFloat = 14
    private static let width: CGFloat = 560
    private static let height: CGFloat = 600
    private static let promptHeight: CGFloat = 180

    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var promptFocused: Bool
    @State private var showsInstructions = true

    private var controls: some View {
        HStack {
            reviewerPicker
            Spacer()
            BusyButton(
                "Review",
                busy: "Reviewing",
                prominent: true,
                disabled: model.isBusy || diff.files.isEmpty
                    || model.reviewInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            ) {
                showsInstructions = false
                promptFocused = false
                await model.start(files: diff.files)
                await diff.reload()
                model.update(files: diff.files)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .hoverHelp("Review the selected diff using the edited prompt")
        }
        .interfaceFont(.body)
    }

    private var reviewerPicker: some View {
        Picker("Reviewer", selection: $model.reviewer) {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                Label {
                    Text(agent.displayName)
                } icon: {
                    Image(agent.iconAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSize, height: Self.iconSize)
                }
                .tag(agent)
            }
        }
        .disabled(model.isBusy)
    }

    private var promptEditor: some View {
        DisclosureGroup("Review prompt", isExpanded: $showsInstructions) {
            TextEditor(text: $model.reviewInstructions)
                .interfaceFont(.body)
                .frame(height: Self.promptHeight)
                .focused($promptFocused)
                .disabled(model.isBusy)
                .accessibilityLabel("Review prompt")
            Text("Edit the instructions or add context. The selected diff is attached automatically.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
        .interfaceFont(.body)
    }

    private var findings: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing) {
                if let review = model.review, review.failure == nil {
                    if review.threads.isEmpty {
                        Text("No findings.").interfaceFont(.body)
                    } else {
                        ForEach(review.threads) { thread in
                            LocalReviewThreadRow(model: model, diff: diff, thread: thread)
                        }
                    }
                } else if model.error == nil {
                    Text("Run a review to see findings here and beneath the changed files.")
                        .interfaceFont(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var makeFixes: some View {
        if let review = model.review, review.failure == nil, review.threads.isEmpty == false {
            BusyButton(
                "Make fixes (\(String(review.remaining)))",
                busy: "Preparing",
                disabled: model.canPrepare == false,
            ) {
                model.showsPrompt = await model.prepare {
                    await diff.reload()
                    return diff.files
                }
            }
            .interfaceFont(.body)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .hoverHelp("Prepare one editable prompt for all unresolved findings")
        }
    }
}
