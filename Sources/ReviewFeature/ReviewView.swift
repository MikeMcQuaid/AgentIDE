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
            ReviewFooterView(model: model)
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
            displayButton(.standard, systemImage: "doc.badge.gearshape", help: "Hide generated files, expand the rest")
            displayButton(.hideAll, systemImage: "eye.slash", help: "Collapse every file to its name")
            displayButton(.showAll, systemImage: "eye", help: "Expand every file, generated included")
            iconButton(
                "textformat",
                help: model.hidesWhitespace
                    ? "Whitespace-only changes are hidden; click to show them"
                    : "Hide whitespace-only changes from the diff",
                isOn: model.hidesWhitespace,
            ) {
                model.hidesWhitespace.toggle()
                Task { await model.reload() }
            }
            Spacer()
            DiffStatText(
                additions: model.visibleFiles.map(\.additions).reduce(0, +),
                deletions: model.visibleFiles.map(\.deletions).reduce(0, +),
            )
            .hoverHelp("Lines added and deleted across the visible files")
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
            .upstream,
            systemImage: "icloud.and.arrow.up",
            title: "Upstream",
            help: model.hasUpstream
                ? "Review commits not yet pushed to this branch's origin ref"
                : "Dimmed until this branch has been pushed",
            disabled: model.hasUpstream == false,
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
            disabled: model.selections.values.allSatisfy(\.isEmpty)
                || model.scope == .branch || model.scope == .upstream,
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

    private func scopeButton(
        _ scope: ReviewModel.Scope,
        systemImage: String,
        title: String,
        help: String,
        disabled: Bool = false,
    ) -> some View {
        iconButton(systemImage, help: help, title: title, isOn: model.scope == scope, disabled: disabled) {
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

    /// One bubble per display mode, like the scope toggles;
    /// generated files show outside the default mode and manual
    /// carets reset on every switch.
    private func displayButton(
        _ mode: ReviewFileDisplay,
        systemImage: String,
        help: String,
    ) -> some View {
        iconButton(systemImage, help: help, title: mode.title, isOn: display == mode) {
            display = mode
            collapseOverrides = [:]
            model.showsGenerated = mode != .standard
        }
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
