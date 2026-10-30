import AppKit
import DashboardFeature
@testable import SanductorData
import SwiftUI
import Testing

struct SetupViewTests {
    // MARK: Internal

    @Test(arguments: [false, true])
    func `setup instructions appear only after a failed check`(requiresSetup: Bool) async throws {
        _ = NSApplication.shared
        let suite = "setup-view-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SetupModel(check: { _ in
            SetupResult(issues: requiresSetup ? [
                SetupIssue(
                    step: .tools,
                    title: "Missing tool",
                    explanation: "Install it",
                    commands: "install",
                    alternative: "",
                ),
            ] : [], agents: [.codexCLI])
        }, defaults: defaults)
        #expect(model.isChecking == false)
        // Freeze the first body before SwiftUI starts its tasks.
        let host = NSHostingView(rootView: SetupView(model: model).body)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutSubtreeIfNeeded()
        #expect(containsInstructions(in: host) == false)
        #expect(host.fittingSize.height > 0)
        #expect(host.fittingSize.width > 0)

        await model.recheck()
        host.rootView = SetupView(model: model).body
        host.layoutSubtreeIfNeeded()
        #expect(containsInstructions(in: host) == requiresSetup)
        #expect((host.fittingSize == .zero) == (requiresSetup == false))
    }

    // MARK: Private

    private func containsInstructions(in view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains { containsInstructions(in: $0) }
    }
}
