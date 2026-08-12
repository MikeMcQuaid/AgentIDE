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
    private static let dividerHeight: CGFloat = 14
    private static let iconPadding: CGFloat = 4
    private static let iconCornerRadius: CGFloat = 5
    private static let iconSelectedOpacity = 0.2
    private static let disabledOpacity = 0.4
    private static let commitListSpacing: CGFloat = 4
    private static let commitLineSpacing: CGFloat = 2
    private static let messageHeight: CGFloat = 88

    /// git's conventional commit message widths.
    private static let subjectLimit = 50
    private static let bodyLimit = 72

    @State private var model: ReviewModel
    @State private var display: ReviewFileDisplay = .standard
    @State private var collapseOverrides: [String: Bool] = [:]

    private let worktreePath: String
    private let service: SessionService
    private let makeModel: () -> ReviewModel

    /// Icon-only controls, every one explained by its tooltip.
    private var toolbar: some View {
        HStack(spacing: Self.captionSpacing) {
            scopeButtons
            Divider().frame(height: Self.dividerHeight)
            iconButton(
                "doc.badge.gearshape",
                help: "Cycle the file display: Default hides generated files, "
                    + "Hide All collapses every file, Show All expands everything",
                title: display.title,
            ) { cycleDisplay() }
            Spacer()
            actionButtons
        }
        .padding(Self.spacing)
    }

    @ViewBuilder private var scopeButtons: some View {
        scopeButton(.uncommitted, systemImage: "pencil", title: "Uncommitted", help: "Review uncommitted changes")
        scopeButton(
            .lastCommit,
            systemImage: "clock",
            title: "Last Commit",
            help: "Review the last commit",
        )
        scopeButton(
            .branch,
            systemImage: "arrow.triangle.branch",
            title: "Branch",
            help: "Review every commit on the branch against its merge base",
        )
    }

    @ViewBuilder private var actionButtons: some View {
        iconButton(
            "tray.and.arrow.down",
            help: "Commit changes the agent left uncommitted; enabled on the uncommitted scope when there are any",
            disabled: model.showsUncommitted == false || model.files.isEmpty,
        ) { Task { await commitOutstanding() } }
        iconButton(
            "arrow.uturn.backward",
            help: "Reject the selected lines: reverse-apply them and amend the commit",
            disabled: model.selections.values.allSatisfy(\.isEmpty) || model.scope == .branch,
        ) { Task { await model.rejectSelected() } }
        iconButton("arrow.clockwise", help: "Reload the diff from git") {
            Task { await model.reload() }
        }
    }

    /// The collapsible file list; the uncommitted scope embeds the
    /// shared editor per file so fixes are typed directly.
    @ViewBuilder private var diffList: some View {
        if model.visibleFiles.isEmpty {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReviewFileListView(
                model: model,
                worktreePath: worktreePath,
                service: service,
                hideAllByDefault: display == .hideAll,
                collapseOverrides: $collapseOverrides,
            )
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
                            Text(commit)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .textSelection(.enabled)
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
                        // Selectable so failures can be copied out.
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
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

    private func scopeButton(
        _ scope: ReviewModel.Scope,
        systemImage: String,
        title: String,
        help: String,
    ) -> some View {
        iconButton(systemImage, help: help, title: title, isOn: model.scope == scope) {
            model.scope = scope
            collapseOverrides = [:]
            Task { await model.reload() }
        }
    }

    /// A one-word title beside the icon where one fits; the action
    /// buttons on the right stay icon-only.
    private func iconButton(
        _ systemImage: String,
        help: String,
        title: String? = nil,
        isOn: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Self.captionSpacing) {
                Image(systemName: systemImage)
                if let title {
                    Text(title).font(.caption)
                }
            }
            .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .padding(Self.iconPadding)
            .background(
                RoundedRectangle(cornerRadius: Self.iconCornerRadius)
                    .fill(isOn ? Color.accentColor.opacity(Self.iconSelectedOpacity) : .clear),
            )
            .contentShape(Rectangle())
            .accessibilityLabel(help)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Self.disabledOpacity : 1)
        // The colour fill alone is invisible to VoiceOver.
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .hoverHelp(help)
    }

    /// Cycles Default, Hide All and Show All; generated files show
    /// outside the default mode and manual carets reset.
    private func cycleDisplay() {
        let all = ReviewFileDisplay.allCases
        let next = ((all.firstIndex(of: display) ?? 0) + 1) % all.count
        display = all[next]
        collapseOverrides = [:]
        model.showsGenerated = display != .standard
    }

    private func commitOutstanding() async {
        do {
            try await service.commitOutstanding(worktreePath: worktreePath)
            await model.reload()
        } catch {
            model.report(error.localizedDescription)
        }
    }
}
