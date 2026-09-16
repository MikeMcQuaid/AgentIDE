import AppKit
import Darwin
import Observation
import SwiftUI
@testable import TerminalUI
import Testing

/// Real shell processes survive navigation and collapsing their container.
@MainActor
struct ShellLifetimeTests {
    // MARK: Internal

    @Observable
    final class State {
        // MARK: Lifecycle

        init(paths: [String]) {
            self.paths = paths
            selected = paths.first
        }

        deinit {
            // The hosting view owns the shells, not the navigation state.
        }

        // MARK: Internal

        var paths: [String]
        var selected: String?
        var isExpanded = true
        var showsShell = true
    }

    @Test
    func `navigation and hiding preserve shells until explicitly closed`() async throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".test-scratch/shell-lifetime-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = State(paths: [directory.path, directory.appendingPathComponent("other").path])
        try FileManager.default.createDirectory(atPath: state.paths[1], withIntermediateDirectories: true)
        let host = NSHostingView(rootView: Shells(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        var spawnedPIDs = [pid_t]()
        defer { close(window, shellPIDs: spawnedPIDs) }
        await wait(in: host) { terminals(in: host).count == 2 && terminals(in: host).allSatisfy(\.process.running) }
        let original = terminals(in: host).map(\.process.shellPid).sorted()
        spawnedPIDs = original
        try #require(original.count == 2)
        #expect(original.allSatisfy { $0 > 0 })

        for (expanded, selected, shellTab) in [
            (true, state.paths.last, true),
            (true, state.paths.first, false),
            (false, state.paths.first, true),
            (true, nil, true),
            (true, state.paths.first, true),
        ] {
            state.isExpanded = expanded
            state.selected = selected
            state.showsShell = shellTab
            let visibleCount = expanded && selected != nil && shellTab ? 1 : 0
            await wait(in: host) { visibleCount == terminals(in: host).count { $0.isHidden == false } }
            #expect(terminals(in: host).map(\.process.shellPid).sorted() == original)
            #expect(terminals(in: host).allSatisfy { $0.frame.width == 400 && $0.process.running })
        }

        state.paths.removeFirst()
        await wait(in: host) { terminals(in: host).count == 1 }
        let remaining = try #require(terminals(in: host).first)
        #expect(original.contains(remaining.process.shellPid))
        #expect(terminals(in: host).count == 1)
    }

    // MARK: Private

    private struct Shells: View {
        let state: State

        var body: some View {
            HStack(spacing: 0) {
                Color.clear
                RetainedPane(isExpanded: state.isExpanded, width: 400) {
                    ZStack {
                        ForEach(state.paths, id: \.self) { path in
                            TerminalPaneView(
                                shellIn: path,
                                environment: ["ZDOTDIR": path],
                                isActive: state.isExpanded && state.showsShell && state.selected == path,
                            )
                        }
                    }
                }
            }
        }
    }

    private func terminals(in view: NSView) -> [PaneTerminalView] {
        if let terminal = view as? PaneTerminalView {
            return [terminal]
        }
        return view.subviews.flatMap { terminals(in: $0) }
    }

    private func close(_ window: NSWindow, shellPIDs: [pid_t]) {
        let views = window.contentView.map { terminals(in: $0) } ?? []
        for view in views {
            view.terminate()
        }
        window.close()
        for pid in Set(shellPIDs + views.map(\.process.shellPid)) where pid > 0 && waitpid(pid, nil, WNOHANG) == 0 {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }

    private func wait(
        in host: NSView,
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            host.layoutSubtreeIfNeeded()
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        #expect(condition(), sourceLocation: sourceLocation)
    }
}
