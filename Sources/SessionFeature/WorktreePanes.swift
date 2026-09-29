import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Keeps visited agents at their full size while sidebar selection changes.
public struct WorktreePanes<Content: View>: View {
    // MARK: Lifecycle

    /// Retains visited sessions, leaving other worktree pages selected-only.
    public init(
        items: [WorktreeItem],
        selection: WorktreeItem?,
        @ViewBuilder content: @escaping (WorktreeItem, Bool) -> Content,
    ) {
        self.items = items
        self.selection = selection
        self.content = content
    }

    // MARK: Public

    public var body: some View {
        ZStack {
            ForEach(items.filter { item in
                item.id != selection?.id && item.session.map { visited.contains($0.name) } == true
            } + (selection.map { [$0] } ?? [])) { item in
                content(item, item.id == selection?.id)
                    .hidden(item.id != selection?.id)
            }
        }
        .onChange(of: selection?.session?.name, initial: true) {
            if let name = selection?.session?.name {
                visited.insert(name)
            }
        }
        .onChange(of: Set(items.compactMap(\.session?.name))) { _, names in
            visited.formIntersection(names)
        }
    }

    // MARK: Private

    @State private var visited: Set<String> = []

    private let items: [WorktreeItem]
    private let selection: WorktreeItem?
    private let content: (WorktreeItem, Bool) -> Content
}
