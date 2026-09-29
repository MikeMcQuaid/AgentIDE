import AgentIDEDomain
import AppKit
import Observation
import SessionFeature
import SwiftUI
import Testing

@MainActor
struct WorktreePanesTests {
    // MARK: Internal

    @Observable
    final class State {
        // MARK: Lifecycle

        init() {
            selection = items.first
        }

        deinit {
            // The hosting view owns the panes.
        }

        // MARK: Internal

        var items = ["one", "two", "unvisited"].map { name in
            WorktreeItem(
                worktree: Worktree(repositoryName: name, repositoryPath: "/" + name, branch: "main", path: "/" + name),
                session: AgentSession(name: name, agent: .codexCLI, status: .running),
                isDirty: false,
                aheadOfUpstream: nil,
                hasUnread: false,
            )
        }

        var selection: WorktreeItem?
    }

    @Test
    func `sidebar switches preserve visited agent views and their full size`() async throws {
        let state = State()
        let host = NSHostingView(rootView: Panes(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await settle(host)
        let first = try #require(panes(in: host).first)
        #expect(panes(in: host).count == 1)
        #expect(first.frame.size == CGSize(width: 800, height: 400))

        state.selection = state.items[1]
        await settle(host)
        let second = try #require(panes(in: host).first { $0.identifier?.rawValue == state.items[1].id })
        #expect(panes(in: host).count == 2)
        #expect(panes(in: host).contains { $0 === first })
        #expect(first.isHidden)

        for selection in [state.items[0], nil, state.items[2].withoutSession(), state.items[1], state.items[0]] {
            state.selection = selection
            await settle(host)
            #expect(panes(in: host).count == (selection?.id == state.items[2].id ? 3 : 2))
            #expect(panes(in: host).contains { $0 === first })
            #expect(panes(in: host).contains { $0 === second })
            #expect(first.isHidden == (selection?.id != state.items[0].id))
            #expect(second.isHidden == (selection?.id != state.items[1].id))
            #expect(panes(in: host).allSatisfy { $0.frame.size == CGSize(width: 800, height: 400) })
        }

        window.setContentSize(CGSize(width: 900, height: 600))
        await settle(host)
        #expect(panes(in: host).allSatisfy { $0.frame.size == CGSize(width: 900, height: 600) })
        state.selection = state.items[1]
        await settle(host)
        #expect(panes(in: host).contains { $0 === second && $0.frame.height == 600 && $0.isHidden == false })

        state.items[0] = state.items[0].withoutSession()
        await settle(host)
        #expect(panes(in: host).count == 1)
        #expect(panes(in: host).first === second)
        state.selection = nil
        state.items.removeAll()
        await settle(host)
        #expect(panes(in: host).isEmpty)
    }

    // MARK: Private

    private struct Panes: View {
        let state: State

        var body: some View {
            WorktreePanes(items: state.items, selection: state.selection) { item, isSelected in
                Pane(id: item.id, isActive: isSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private struct Pane: NSViewRepresentable {
        let id: String
        let isActive: Bool

        func makeNSView(context _: Context) -> NSView {
            let view = NSView()
            view.identifier = NSUserInterfaceItemIdentifier(id)
            return view
        }

        func updateNSView(_ view: NSView, context _: Context) {
            view.isHidden = isActive == false
        }
    }

    private func panes(in view: NSView) -> [NSView] {
        if view.identifier != nil {
            return [view]
        }
        return view.subviews.flatMap { panes(in: $0) }
    }

    private func settle(_ host: NSView) async {
        for _ in 0 ..< 5 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
