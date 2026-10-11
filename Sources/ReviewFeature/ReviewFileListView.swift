import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - ReviewFileListView

/// The review pane's file list: collapsible diffs, or inline
/// editors in the uncommitted scope so fixes are typed directly.
struct ReviewFileListView: View {
    // MARK: Internal

    let model: ReviewModel
    @Bindable var localReview: LocalReviewModel
    let worktreePath: String

    /// Whether files start collapsed (the Hide All display mode);
    /// the per-file carets override it.
    let hideAllByDefault: Bool

    @Binding var collapseOverrides: [String: Bool]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Self.spacing) {
                    if conversations.isEmpty == false {
                        HStack {
                            Text("Conversations").interfaceFont(.headline)
                            Spacer()
                            CopyReviewConversationsButton(threads: conversations)
                        }
                    }
                    ForEach(model.files) { file in
                        fileSection(file)
                    }
                    unplacedConversations
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

    @ViewBuilder var unplacedConversations: some View {
        let paths = Set(model.files.map(\.path))
        let local = (localReview.review?.threads ?? []).filter { paths.contains($0.path) == false }
        let remote = model.threads.filter { paths.contains($0.path) == false }
        if local.isEmpty == false || remote.isEmpty == false {
            Text("Outside the selected diff").interfaceFont(.callout).foregroundStyle(.secondary)
            ForEach(local) { LocalReviewThreadRow(model: localReview, diff: model, thread: $0) }
            ForEach(remote) { remoteThread($0) }
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 8

    @AppStorage(UtilityTabTarget.pullRequestCacheKey)
    private var automationGeneration = 0

    private var conversations: [ReviewThread] {
        model.threads + (localReview.review?.threads ?? [])
    }

    @ViewBuilder
    private func fileSection(_ file: DiffFile) -> some View {
        // Every scope leads with the diff, uncommitted included: it
        // once showed the whole file in an editor instead, which read
        // as a broken diff; uncommitted files edit in the diff itself.
        DiffFileView(
            file: file,
            model: model,
            isCollapsed: isCollapsed(file),
            onToggleCollapse: { toggleCollapse(file) },
            onEdit: {
                FileOpener.open(relativePath: file.path, line: nil, worktreePath: worktreePath)
            },
            conversations: { AnyView(threads(in: file, hunk: $0)) },
        )
        if isCollapsed(file) == false {
            threads(in: file, hunk: nil)
        }
    }

    @ViewBuilder
    private func threads(in file: DiffFile, hunk: Int?) -> some View {
        ForEach((localReview.review?.threads ?? []).filter { thread in
            thread.path == file.path && (localReview.isOutdated ? nil : file.hunkIndex(containing: thread.line)) == hunk
        }) { thread in
            LocalReviewThreadRow(model: localReview, diff: model, thread: thread, showsCodeContext: hunk == nil)
        }
        ForEach(model.threads(for: file.path).filter { file.hunkIndex(containing: $0.line) == hunk }) { thread in
            remoteThread(thread)
        }
    }

    private func remoteThread(_ thread: ReviewThread) -> some View {
        ReviewThreadRow(
            thread: thread,
            onEdit: { FileOpener.open(relativePath: thread.path, line: thread.line, worktreePath: worktreePath) },
            onToggleResolved: { await model.toggleResolved(thread) },
            onToggleResolveOnPush: { await model.toggleResolveOnPush(thread) },
            isPendingResolution: pendingResolution(thread),
        )
    }

    private func pendingResolution(_ thread: ReviewThread) -> Bool {
        _ = automationGeneration
        return model.pendingResolution(thread)
    }

    private func isCollapsed(_ file: DiffFile) -> Bool {
        // Generated files always start collapsed, whatever the
        // expand-all state says; only their own caret opens them.
        // New files start open like any other: what an agent added
        // is exactly what a review needs to read.
        collapseOverrides[file.path] ?? (hideAllByDefault || model.isGenerated(file.path))
    }

    private func toggleCollapse(_ file: DiffFile) {
        collapseOverrides[file.path] = isCollapsed(file) == false
    }
}
