import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The one session-creation form, shared by the New Session sheet and
/// the per-worktree pane: source (typed prompt, or an open issue, pull
/// request or security advisory picked from the repository), agent,
/// model and effort.
struct AgentSessionForm: View {
    // MARK: Internal

    /// What the user chose, handed to the submit action.
    struct Submission {
        let source: PromptSource
        let number: Int?
        let ghsaID: String?
        let prompt: String
        let context: String
        let agent: AgentKind
        let options: AgentLaunchOptions
    }

    enum PromptSource: CaseIterable {
        case prompt
        case issue
        case pullRequest
        case advisory

        // MARK: Internal

        var title: String {
            switch self {
            case .prompt:
                "Prompt"

            case .issue:
                "Issue"

            case .pullRequest:
                "PR"

            case .advisory:
                "Advisory"
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
            .hoverHelp(
                "Where the prompt comes from: typed text, an open issue or pull request,"
                    + " or a security advisory in triage or draft",
            )
            AgentOptionPickers(
                agent: agent,
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
                submitButton
            }
        }
        .task(id: repository?.id ?? "") { await reloadSources() }
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let promptHeight: CGFloat = 140
    private static let contextHeight: CGFloat = 70

    @State private var source: PromptSource = .prompt
    /// The last agent, model and effort come back next time: the
    /// agent persists by name beside the model and effort that
    /// always did, because a persisted Codex model over a fresh
    /// default of Claude once launched Claude with a GPT id.
    @AppStorage("agentKind")
    private var agentKindName = AgentKind.claudeCode.rawValue

    @State private var number: Int?
    @State private var ghsaID: String?

    /// Guards against double submission: creating a worktree takes
    /// seconds, and a second click during it started a second
    /// session.
    @State private var isStarting = false
    @State private var issues: [IssueSummary] = []
    @State private var pullRequests: [PullRequestSummary] = []
    /// Until the fetch answers, an empty list is not yet proven empty.
    @State private var isLoadingSources = false
    /// Read only while the Advisory source shows, and never cached:
    /// the titles describe unpublished vulnerabilities.
    @State private var advisories: [SecurityAdvisorySummary] = []
    @State private var isLoadingAdvisories = false
    /// The one thing typed here, whichever source is chosen: the
    /// whole prompt when there is no issue or pull request, and what
    /// to say about one when there is. Two fields meant choosing an
    /// issue after typing looked exactly like the app throwing the
    /// typing away.
    @AppStorage("newSessionPrompt")
    private var prompt = ""
    @AppStorage("agentModel")
    private var agentModel = ""
    @AppStorage("agentEffort")
    private var agentEffort = ""

    private var agent: Binding<AgentKind> {
        Binding(
            get: { AgentKind(rawValue: agentKindName) ?? .claudeCode },
            set: { agentKindName = $0.rawValue },
        )
    }

    private var submitDisabled: Bool {
        guard repository != nil, agentModel.isEmpty == false, agentEffort.isEmpty == false else {
            return true
        }

        switch source {
        case .prompt:
            return prompt.isEmpty

        case .issue,
             .pullRequest:
            return number == nil

        case .advisory:
            return ghsaID == nil
        }
    }

    /// The submit button; Cmd-Return also submits from inside the
    /// prompt editor, where plain Return types a newline, via a
    /// hidden button carrying the second shortcut.
    private var submitButton: some View {
        Button(isStarting ? "Starting…" : submitTitle) { submit() }
            .keyboardShortcut(.defaultAction)
            .disabled(submitDisabled || isStarting)
            .hoverHelp(submitHelp)
            .background(
                Button("Start with Cmd-Return") { submit() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(submitDisabled || isStarting)
                    .hidden(),
            )
    }

    @ViewBuilder private var sourceFields: some View {
        switch source {
        case .prompt:
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: Self.promptHeight)
                .border(.separator)

        case .advisory,
             .issue,
             .pullRequest:
            numberPicker
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: Self.contextHeight)
                .border(.separator)
                .hoverHelp("Context appended to the fetched title and body; anything typed first is kept")
        }
    }

    @ViewBuilder private var numberPicker: some View {
        if repository == nil {
            Text("Pick a repository first.").font(.callout).foregroundStyle(.secondary)
        } else if source == .issue {
            ReferencedItemPicker(
                "Issue",
                selection: $number,
                items: issues,
                placeholder: "Choose an open issue",
                searchPrompt: "Find an issue by number or title",
                loadingTitle: "Listing open issues…",
                emptyTitle: "No open issues",
                isLoading: isLoadingSources,
            )
            .hoverHelp("The repository's open issues; the pick becomes the prompt")
        } else if source == .advisory {
            ReferencedItemPicker(
                "Security advisory",
                selection: $ghsaID,
                items: advisories,
                placeholder: "Choose an advisory in triage or draft",
                searchPrompt: "Find an advisory by GHSA id or title",
                loadingTitle: "Listing advisories in triage or draft…",
                emptyTitle: "No advisories in triage or draft",
                isLoading: isLoadingAdvisories,
            )
            .hoverHelp(
                "The repository's security advisories still in triage or draft; the pick becomes the prompt,"
                    + " and the agent is told to keep its commits and pull request quiet about it",
            )
            .task(id: repository?.id ?? "") { await reloadAdvisories() }
        } else {
            ReferencedItemPicker(
                "Pull request",
                selection: $number,
                items: pullRequests,
                placeholder: "Choose an open pull request",
                searchPrompt: "Find a pull request by number or title",
                loadingTitle: "Listing open pull requests…",
                emptyTitle: "No open pull requests",
                isLoading: isLoadingSources,
            )
            .hoverHelp("The repository's open pull requests; its branch is checked out to work on directly")
        }
    }

    private func reloadSources() async {
        number = nil
        ghsaID = nil
        advisories = []
        guard let repository else {
            issues = []
            pullRequests = []
            isLoadingSources = false
            return
        }

        // The cache paints the pickers instantly; the fetch refreshes
        // them in place.
        isLoadingSources = true
        let cached = model.cachedOpenSources(repository: repository)
        issues = cached.issues
        pullRequests = cached.pullRequests
        // A fetch for a repository no longer picked must not overwrite
        // the current one's lists or end its loading state.
        let freshIssues = await model.openIssues(repository: repository)
        guard Task.isCancelled == false else {
            return
        }

        issues = freshIssues
        let freshPullRequests = await model.openPullRequests(repository: repository)
        guard Task.isCancelled == false else {
            return
        }

        pullRequests = freshPullRequests
        isLoadingSources = false
    }

    private func reloadAdvisories() async {
        guard let repository else {
            return
        }

        isLoadingAdvisories = true
        let fresh = await model.securityAdvisories(repository: repository)
        guard Task.isCancelled == false else {
            return
        }

        advisories = fresh
        isLoadingAdvisories = false
    }

    private func submit() {
        guard isStarting == false else {
            return
        }

        isStarting = true
        let submission = Submission(
            source: source,
            number: number,
            ghsaID: ghsaID,
            prompt: source == .prompt ? prompt : "",
            context: source == .prompt ? "" : prompt,
            agent: agent.wrappedValue,
            options: AgentLaunchOptions(
                model: agentModel.isEmpty ? nil : agentModel,
                effort: agentEffort.isEmpty ? nil : agentEffort,
            ),
        )
        Task {
            await onSubmit(submission)
            isStarting = false
            prompt = ""
        }
    }
}
