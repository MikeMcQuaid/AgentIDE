import SanductorData
import SanductorDomain
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
        /// The picked issues or pull requests, one launch each.
        let numbers: [Int]
        let ghsaID: String?
        let prompt: String
        let context: String
        let agent: AgentKind
        let options: AgentLaunchOptions
    }

    /// Where the draft is kept between forms and launches.
    static let promptKey = "newSessionPrompt"

    let model: DashboardModel

    /// The repository the session targets, nil until picked.
    let repository: Repository?

    /// The worktree this form starts an agent in, nil on the new
    /// session form; a failed launch's retry finds its form by it.
    var worktreePath: String?

    /// Whether the issue and pull request pickers take several picks,
    /// each its own session; a worktree's own form is one place.
    var picksSeveral = false

    let submitTitle: String
    let submitHelp: String

    var onSourceChange: (@MainActor (PromptSource) -> Void)?
    let onSubmit: @MainActor (Submission) async -> Void

    var body: some View {
        Group {
            if isStarting {
                if let progress = model.launchProgresses[worktreePath ?? model.selection?.id ?? ""] {
                    LaunchProgressView("Starting the agent…", progress: progress)
                } else {
                    LaunchProgressView("Preparing the agent launch…", waitingOn: "the launch to begin")
                }
            } else {
                form
            }
        }
        .task(id: repository?.id ?? "") { await reloadSources() }
        .onChange(of: source) { onSourceChange?(source) }
        // A worktree's form is already on screen when its retry asks.
        .onChange(of: model.launchRetry) { applyRetry() }
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

    /// Kept per source: issues and pull requests share one numbering,
    /// so an issue's number carried over to the pull request picker
    /// would start a launch the picker did not show.
    @State private var issueNumbers: Set<Int> = []
    @State private var pullRequestNumbers: Set<Int> = []
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
    @AppStorage(Self.promptKey)
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
            return pickedNumbers.isEmpty

        case .advisory:
            return ghsaID == nil
        }
    }

    private var pickedNumbers: Set<Int> {
        switch source {
        case .issue:
            issueNumbers

        case .pullRequest:
            pullRequestNumbers

        case .advisory,
             .prompt:
            []
        }
    }

    private var startTitle: String {
        if pickedNumbers.count > 1 {
            "Start " + String(pickedNumbers.count) + " agents"
        } else {
            submitTitle
        }
    }

    private var form: some View {
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
                submitButton
            }
        }
    }

    /// The submit button; Cmd-Return also submits from inside the
    /// prompt editor, where plain Return types a newline, via a
    /// hidden button carrying the second shortcut.
    private var submitButton: some View {
        Button(isStarting ? "Starting…" : startTitle) { submit() }
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
                .interfaceFont(.body)
                .frame(minHeight: Self.promptHeight)
                .border(.separator)

        case .advisory,
             .issue,
             .pullRequest:
            SourcePicker(
                source: source,
                repository: repository,
                picksSeveral: picksSeveral,
                issueNumbers: $issueNumbers,
                pullRequestNumbers: $pullRequestNumbers,
                ghsaID: $ghsaID,
                issues: issues,
                pullRequests: pullRequests,
                advisories: advisories,
                isLoadingSources: isLoadingSources,
                isLoadingAdvisories: isLoadingAdvisories,
                reloadAdvisories: reloadAdvisories,
            )
            TextEditor(text: $prompt)
                .interfaceFont(.body)
                .frame(minHeight: Self.contextHeight)
                .border(.separator)
                .hoverHelp("Context appended to each fetched title and body; anything typed first is kept")
        }
    }

    private func reloadSources() async {
        issueNumbers = []
        pullRequestNumbers = []
        ghsaID = nil
        advisories = []
        applyRetry()
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

    /// Takes back a failed launch's draft meant for this form: its
    /// text, source and pick.
    private func applyRetry() {
        guard let retry = model.launchRetry, retry.worktreePath == worktreePath,
              retry.repositoryPath == repository?.path
        else {
            return
        }

        model.launchRetry = nil
        source = retry.draft.source
        let picks = Set([retry.draft.number].compactMap(\.self))
        issueNumbers = retry.draft.source == .issue ? picks : []
        pullRequestNumbers = retry.draft.source == .pullRequest ? picks : []
        ghsaID = retry.draft.ghsaID
        prompt = retry.draft.text
        agentKindName = retry.draft.agent.rawValue
        let choices = model.launchChoices(for: retry.draft.agent)
        agentModel = retry.draft.options.model ?? choices.defaultModel
        agentEffort = retry.draft.options.effort ?? choices.defaultEffort
    }

    private func submit() {
        guard isStarting == false else {
            return
        }

        isStarting = true
        let submission = Submission(
            source: source,
            numbers: pickedNumbers.sorted(),
            ghsaID: ghsaID,
            prompt: source == .prompt ? prompt : "",
            context: source == .prompt ? "" : prompt,
            agent: agent.wrappedValue,
            options: AgentLaunchOptions(
                model: agentModel.isEmpty ? nil : agentModel,
                effort: agentEffort.isEmpty ? nil : agentEffort,
            ),
        )
        // Cleared now, not once the launch lands: the next form
        // opened while this launch runs must not start from the
        // draft it is starting. A failure keeps the draft for its
        // retry (`LaunchRetry`).
        prompt = ""
        Task {
            await onSubmit(submission)
            isStarting = false
        }
    }
}
