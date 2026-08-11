import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A pull-request-style review of the worktree's changes with
/// per-line rejection, commit message editing and a file editor. The
/// scope toggles between the last commit and the whole branch against
/// its merge base.
public struct ReviewView: View {
    // MARK: Lifecycle

    /// Creates the review view for a worktree.
    public init(worktree: Worktree, git: GitClient, service: SessionService) {
        worktreePath = worktree.path
        self.service = service
        let builder = {
            ReviewModel(worktreePath: worktree.path, git: git) {
                await service.reviewBase(for: worktree)
            }
        }
        makeModel = builder
        _model = State(initialValue: builder())
    }

    // MARK: Public

    /// The toolbar, diff list and commit message editor.
    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            diffList
            Divider()
            footer
        }
        // The model is rebuilt whenever the worktree changes: state
        // survives the view struct's re-initialisation, so the first
        // worktree's model would otherwise review every one.
        .task(id: worktreePath) {
            model = makeModel()
            await model.reload()
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let captionSpacing: CGFloat = 2
    private static let commitListSpacing: CGFloat = 4
    private static let commitLineSpacing: CGFloat = 2
    private static let messageHeight: CGFloat = 88

    /// git's conventional commit message widths.
    private static let subjectLimit = 50
    private static let bodyLimit = 72

    @State private var model: ReviewModel

    private let worktreePath: String
    private let service: SessionService
    private let makeModel: () -> ReviewModel

    private var scopeHelp: String {
        """
        Last commit reviews the newest commit (or uncommitted changes); \
        Branch reviews every commit against the pull request's base \
        branch, or the default branch without one
        """
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: Self.captionSpacing) {
            HStack {
                Picker("Scope", selection: $model.scope) {
                    Text(model.showsUncommitted ? "Uncommitted" : "Last commit").tag(ReviewModel.Scope.lastCommit)
                    Text("Branch").tag(ReviewModel.Scope.branch)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
                .onChange(of: model.scope) { Task { await model.reload() } }
                .hoverHelp(scopeHelp)
                Toggle("Generated", isOn: $model.showsGenerated)
                    .hoverHelp(
                        "Reveal files hidden as generated: lockfiles, Xcode projects, asset catalogues and similar",
                    )
                Spacer()
                Button("Commit outstanding") { Task { await commitOutstanding() } }
                    .disabled(model.showsUncommitted == false)
                    .hoverHelp("Commit changes the agent left uncommitted; disabled when the worktree is clean")
                Button("Reject selected lines") { Task { await model.rejectSelected() } }
                    .disabled(model.selections.values.allSatisfy(\.isEmpty) || model.scope == .branch)
                    .hoverHelp("Reverse-apply the selected lines and amend the commit; last commit scope only")
                Button("Refresh") { Task { await model.reload() } }
                    .hoverHelp("Reload the diff from git")
            }
            if model.scope == .branch, let base = model.branchBase {
                Text("vs " + base).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(Self.spacing)
    }

    /// Editing a file jumps to the Editor tab rather than opening a
    /// duplicate editor surface; Cmd-click opens the external editor.
    private var diffList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(model.visibleFiles) { file in
                    DiffFileView(file: file, model: model) {
                        FileOpener.open(relativePath: file.path, line: nil, worktreePath: worktreePath)
                    }
                }
                if model.visibleFiles.isEmpty {
                    ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                }
            }
            .padding(Self.spacing)
        }
    }

    /// Last commit scope edits the message; branch scope lists every
    /// commit under review instead.
    @ViewBuilder private var footer: some View {
        if model.scope == .branch {
            VStack(alignment: .leading, spacing: Self.commitListSpacing) {
                Text("Commits under review").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.commitLineSpacing) {
                        ForEach(model.branchCommits, id: \.self) { commit in
                            Text(commit).font(.caption.monospaced()).lineLimit(1)
                        }
                        if model.branchCommits.isEmpty {
                            Text("No commits beyond the base branch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: Self.messageHeight)
            }
            .padding(Self.spacing)
        } else {
            VStack(alignment: .leading, spacing: Self.spacing) {
                TextEditor(text: $model.commitMessage)
                    .font(.body.monospaced())
                    .frame(height: Self.messageHeight)
                    .border(.separator)
                    .overlay(alignment: .topLeading) { messageGuides }
                    .hoverHelp(
                        "The full commit message; the guides mark 50 columns for the subject and 72 for the body",
                    )
                HStack {
                    Button("Amend message") { Task { await model.saveCommitMessage() } }
                        .disabled(model.showsUncommitted)
                        .hoverHelp("Rewrite the last commit's message")
                    messageLengths
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
            }
            .padding(Self.spacing)
        }
    }

    /// Vertical rules at git's conventional 50 and 72 column widths,
    /// positioned by the editor's monospaced character width.
    private var messageGuides: some View {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Text measurement is an AppKit API; NSString is its input.
        // swiftlint:disable:next legacy_objc_type
        let characterWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let inset: CGFloat = 5
        return ZStack(alignment: .topLeading) {
            ForEach([Self.subjectLimit, Self.bodyLimit], id: \.self) { columns in
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .offset(x: inset + characterWidth * CGFloat(columns))
            }
        }
        .allowsHitTesting(false)
    }

    /// Live counts against the conventional widths, red when over.
    private var messageLengths: some View {
        let lines = model.commitMessage.split(separator: "\n", omittingEmptySubsequences: false)
        let subject = lines.first.map(String.init) ?? ""
        let widestBody = lines.dropFirst().map(\.count).max() ?? 0
        return HStack(spacing: Self.spacing) {
            Text("subject \(subject.count)/\(Self.subjectLimit)")
                .foregroundStyle(subject.count > Self.subjectLimit ? .red : .secondary)
            Text("body \(widestBody)/\(Self.bodyLimit)")
                .foregroundStyle(widestBody > Self.bodyLimit ? .red : .secondary)
        }
        .font(.caption.monospaced())
        .hoverHelp("git convention: subjects at most 50 characters, body lines wrapped at 72")
    }

    private func commitOutstanding() async {
        try? await service.commitOutstanding(worktreePath: worktreePath)
        await model.reload()
    }
}
