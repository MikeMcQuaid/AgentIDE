import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - ReviewFileListView

/// The review pane's file list: collapsible diffs, or inline
/// editors in the uncommitted scope so fixes are typed directly.
struct ReviewFileListView: View {
    // MARK: Internal

    let model: ReviewModel
    let worktreePath: String
    let service: SessionService

    /// Whether files start collapsed (the Hide All display mode);
    /// the per-file carets override it.
    let hideAllByDefault: Bool

    @Binding var collapseOverrides: [String: Bool]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Self.spacing) {
                    ForEach(model.files) { file in
                        fileSection(file)
                    }
                }
                .padding(Self.spacing)
            }
            // A match in a collapsed file has nothing on screen to
            // scroll to, which SwiftUI treats as no request at all.
            .onChange(of: model.currentFindTarget) { _, target in
                guard let target else {
                    return
                }

                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let editorMinimumHeight: CGFloat = 240
    private static let editorMaximumHeight: CGFloat = 420

    @ViewBuilder
    private func fileSection(_ file: DiffFile) -> some View {
        // Every scope leads with the diff, uncommitted included: it
        // once showed the whole file in an editor instead, which read
        // as a broken diff. Uncommitted files keep that editor for
        // fixing in place, below their diff.
        DiffFileView(
            file: file,
            model: model,
            isCollapsed: isCollapsed(file),
            onToggleCollapse: { toggleCollapse(file) },
            onEdit: {
                FileOpener.open(relativePath: file.path, line: nil, worktreePath: worktreePath)
            },
        )
        if model.showsUncommitted, isCollapsed(file) == false, file.isNew == false {
            FileEditorView(
                worktreePath: worktreePath,
                relativePath: file.path,
                service: service,
                showsClose: false,
            )
            .frame(minHeight: Self.editorMinimumHeight, maxHeight: Self.editorMaximumHeight)
        }
        if isCollapsed(file) == false {
            ForEach(model.threads(for: file.path)) { thread in
                ReviewThreadRow(
                    thread: thread,
                    onEdit: {
                        FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: worktreePath)
                    },
                    onToggleResolved: { await model.toggleResolved(thread) },
                )
            }
        }
    }

    private func isCollapsed(_ file: DiffFile) -> Bool {
        // Generated files always start collapsed, whatever the
        // expand-all state says; only their own caret opens them.
        collapseOverrides[file.path] ?? (hideAllByDefault || model.isGenerated(file.path) || file.isNew)
    }

    private func toggleCollapse(_ file: DiffFile) {
        collapseOverrides[file.path] = isCollapsed(file) == false
    }
}
