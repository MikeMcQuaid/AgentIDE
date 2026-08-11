import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The one session-creation form, shared by the New Session sheet and
/// the per-worktree pane: source (typed prompt, or an open issue or
/// pull request picked from the repository), agent, model and effort.
struct AgentSessionForm: View {
    // MARK: Internal

    /// What the user chose, handed to the submit action.
    struct Submission {
        let source: PromptSource
        let number: Int?
        let prompt: String
        let context: String
        let agent: AgentKind
        let options: AgentLaunchOptions
    }

    enum PromptSource: CaseIterable {
        case prompt
        case issue
        case pullRequest

        // MARK: Internal

        var title: String {
            switch self {
            case .prompt:
                "Prompt"

            case .issue:
                "Issue"

            case .pullRequest:
                "PR"
            }
        }
    }

    let model: DashboardModel

    /// The repository the session targets, nil until picked.
    let repository: Repository?

    let submitTitle: String
    let submitHelp: String
    let onSubmit: @MainActor (Submission) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Picker("Source", selection: $source) {
                ForEach(PromptSource.allCases, id: \.self) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .hoverHelp("Where the prompt comes from: typed text, or an open issue or pull request")
            AgentOptionPickers(
                agent: $agent,
                model: $agentModel,
                effort: $agentEffort,
            ) { model.launchChoices(for: $0) }
            sourceFields
            HStack {
                Spacer()
                if isStarting {
                    ProgressView()
                        .controlSize(.small)
                        .hoverHelp("Creating the worktree and starting the agent")
                }
                Button(isStarting ? "Starting…" : submitTitle) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitDisabled || isStarting)
                    .hoverHelp(submitHelp)
            }
        }
        .task(id: repository?.id ?? "") { await reloadSources() }
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let promptHeight: CGFloat = 140
    private static let contextHeight: CGFloat = 70

    @State private var source: PromptSource = .prompt
    @State private var agent: AgentKind = .claudeCode
    @State private var number: Int?

    /// Guards against double submission: creating a worktree takes
    /// seconds, and a second click during it started a second
    /// session.
    @State private var isStarting = false
    @State private var issues: [IssueSummary] = []
    @State private var pullRequests: [PullRequestSummary] = []
    @AppStorage("newSessionPrompt")
    private var prompt = ""
    @AppStorage("newSessionContext")
    private var context = ""
    @AppStorage("agentModel")
    private var agentModel = ""
    @AppStorage("agentEffort")
    private var agentEffort = ""

    private var submitDisabled: Bool {
        guard repository != nil else {
            return true
        }

        switch source {
        case .prompt:
            return prompt.isEmpty

        case .issue,
             .pullRequest:
            return number == nil
        }
    }

    @ViewBuilder private var sourceFields: some View {
        switch source {
        case .prompt:
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: Self.promptHeight)
                .border(.separator)

        case .issue,
             .pullRequest:
            numberPicker
            TextEditor(text: $context)
                .font(.body)
                .frame(minHeight: Self.contextHeight)
                .border(.separator)
                .hoverHelp("Additional context appended to the fetched title and body")
        }
    }

    @ViewBuilder private var numberPicker: some View {
        if repository == nil {
            Text("Pick a repository first.").font(.callout).foregroundStyle(.secondary)
        } else if source == .issue {
            Picker("Issue", selection: $number) {
                Text("Choose an open issue").tag(Int?.none)
                ForEach(issues) { issue in
                    Text("#" + String(issue.number) + " " + issue.title).tag(Int?.some(issue.number))
                }
            }
            .labelsHidden()
            .hoverHelp("The repository's open issues; the pick becomes the prompt")
        } else {
            Picker("Pull request", selection: $number) {
                Text("Choose an open pull request").tag(Int?.none)
                ForEach(pullRequests) { pullRequest in
                    Text("#" + String(pullRequest.number) + " " + pullRequest.title)
                        .tag(Int?.some(pullRequest.number))
                }
            }
            .labelsHidden()
            .hoverHelp("The repository's open pull requests; its branch is checked out to work on directly")
        }
    }

    private func reloadSources() async {
        number = nil
        guard let repository else {
            issues = []
            pullRequests = []
            return
        }

        // The cache paints the pickers instantly; the fetch refreshes
        // them in place.
        let cached = model.cachedOpenSources(repository: repository)
        issues = cached.issues
        pullRequests = cached.pullRequests
        issues = await model.openIssues(repository: repository)
        pullRequests = await model.openPullRequests(repository: repository)
    }

    private func submit() {
        guard isStarting == false else {
            return
        }

        isStarting = true
        let submission = Submission(
            source: source,
            number: number,
            prompt: prompt,
            context: context,
            agent: agent,
            options: AgentLaunchOptions(
                model: agentModel.isEmpty ? nil : agentModel,
                effort: agentEffort.isEmpty ? nil : agentEffort,
            ),
        )
        Task {
            await onSubmit(submission)
            isStarting = false
            if source == .prompt {
                prompt = ""
            } else {
                context = ""
            }
        }
    }
}
