import AgentIDEData
import AppKit
import SwiftUI
@testable import TerminalUI
import Testing

/// Preferences redraw a mounted view, with the original typography until changed.
@MainActor
struct FontPreferencesTests {
    // MARK: Internal

    @Test
    func `font settings preserve defaults and update mounted views`() async throws {
        let suite = "FontPreferencesTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recording = Recording()
        let host = NSHostingView(rootView: Probe(recording: recording).defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        await wait { recording.snapshot != nil }

        let original = try #require(recording.snapshot)
        #expect(original.code == (NSFont(name: "SFMono-Regular", size: 13)
                ?? .monospacedSystemFont(ofSize: 13, weight: .regular)))
        #expect(original.repository == .subheadline.weight(.semibold))
        #expect(original.name == .system(.callout, design: .monospaced))
        #expect(original.smallName == .system(.caption, design: .monospaced))
        #expect(original.tab == .callout)
        #expect(original.badge == .caption.bold())

        defaults.set(18.0, forKey: AppSettings.codeFontSizeKey)
        defaults.set("Menlo-Regular", forKey: AppSettings.codeFontNameKey)
        await wait { recording.snapshot?.code == NSFont(name: "Menlo-Regular", size: 18) }

        defaults.set(19.0, forKey: AppSettings.repositoryFontSizeKey)
        await wait { recording.snapshot?.repository == .system(size: 19).weight(.semibold) }
        defaults.set("Helvetica", forKey: AppSettings.repositoryFontNameKey)
        let repositoryFont = try #require(NSFont(name: "Helvetica", size: 19))
        await wait { recording.snapshot?.repository == Font(repositoryFont).weight(.semibold) }
        #expect(recording.snapshot?.name == original.name)
        #expect(recording.snapshot?.tab == original.tab)

        defaults.set(NameStyle.defaultPointSize + 3, forKey: AppSettings.nameFontSizeKey)
        await wait { recording.snapshot?.name != original.name }
        #expect(recording.snapshot?.smallName != original.smallName)
        defaults.set("Menlo-Regular", forKey: AppSettings.nameFontNameKey)
        let nameFont = try #require(NSFont(name: "Menlo-Regular", size: NameStyle.defaultPointSize + 3))
        await wait { recording.snapshot?.name == Font(nameFont) }

        defaults.set(17.0, forKey: AppSettings.tabFontSizeKey)
        defaults.set("Helvetica", forKey: AppSettings.tabFontNameKey)
        let tabFont = try #require(NSFont(name: "Helvetica", size: 17))
        await wait { recording.snapshot?.tab == Font(tabFont) }
        #expect(recording.snapshot?.badge != original.badge)

        defaults.set(CodeStyle.defaultFontName, forKey: AppSettings.codeFontNameKey)
        defaults.set(CodeStyle.defaultPointSize, forKey: AppSettings.codeFontSizeKey)
        defaults.set("", forKey: AppSettings.repositoryFontNameKey)
        defaults.set(RepositoryStyle.defaultPointSize, forKey: AppSettings.repositoryFontSizeKey)
        defaults.set("", forKey: AppSettings.nameFontNameKey)
        defaults.set(NameStyle.defaultPointSize, forKey: AppSettings.nameFontSizeKey)
        defaults.set("", forKey: AppSettings.tabFontNameKey)
        defaults.set(TabStyle.defaultPointSize, forKey: AppSettings.tabFontSizeKey)
        await wait { recording.snapshot == original }
        #expect(recording.creations == 1)
        #expect(host.subviews.isEmpty == false)
    }

    @Test
    func `interface text moves every style and leaves names alone`() async throws {
        let suite = "FontPreferencesTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recording = Recording()
        let host = NSHostingView(rootView: Probe(recording: recording).defaultAppStorage(defaults))
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        await wait { recording.snapshot != nil }

        let original = try #require(recording.snapshot)
        #expect(original.interface == .caption)
        #expect(original.interfaceHeading == .headline)
        #expect(original.interfaceCode == .callout.monospaced())
        #expect(original.appKitHeading.fontDescriptor.symbolicTraits.contains(.bold))

        let caption = NSFont.preferredFont(forTextStyle: .caption1).pointSize
        let callout = NSFont.preferredFont(forTextStyle: .callout).pointSize
        let headline = NSFont.preferredFont(forTextStyle: .headline).pointSize
        defaults.set(InterfaceStyle.defaultPointSize + 4, forKey: AppSettings.interfaceFontSizeKey)
        await wait { recording.snapshot?.interface == .system(size: caption + 4) }
        #expect(recording.snapshot?.interfaceHeading == .system(size: headline + 4, weight: .bold))
        #expect(recording.snapshot?.interfaceCode == .system(size: callout + 4).monospaced())
        #expect(recording.snapshot?.appKitHeading.pointSize == headline + 4)
        #expect(recording.snapshot?.appKitHeading.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(recording.snapshot?.name == original.name)
        defaults.set("Helvetica", forKey: AppSettings.interfaceFontNameKey)
        let interfaceFont = try #require(NSFont(name: "Helvetica", size: caption + 4))
        await wait { recording.snapshot?.interface == Font(interfaceFont) }
        #expect(recording.snapshot?.appKitHeading.familyName == "Helvetica")
        #expect(recording.snapshot?.appKitHeading.fontDescriptor.symbolicTraits.contains(.bold) == true)
        // Monospaced text keeps its columns whatever face was chosen.
        #expect(recording.snapshot?.interfaceCode == .system(size: callout + 4).monospaced())

        defaults.set("", forKey: AppSettings.interfaceFontNameKey)
        defaults.set(InterfaceStyle.defaultPointSize, forKey: AppSettings.interfaceFontSizeKey)
        await wait { recording.snapshot == original }
    }

    // MARK: Private

    private struct Snapshot: Equatable {
        let code: NSFont
        let repository: Font
        let name: Font
        let smallName: Font
        let tab: Font
        let badge: Font
        let interface: Font
        let interfaceHeading: Font
        let interfaceCode: Font
        let appKitHeading: NSFont
    }

    private final class Recording {
        // MARK: Lifecycle

        deinit {
            // Only stores the last rendered values.
        }

        // MARK: Internal

        var snapshot: Snapshot?
        var creations = 0
    }

    private struct Probe: NSViewRepresentable {
        // MARK: Internal

        let recording: Recording

        func makeNSView(context _: Context) -> NSView {
            recording.creations += 1
            return NSView()
        }

        func updateNSView(_: NSView, context _: Context) {
            recording.snapshot = Snapshot(
                code: codeStyle.appKitFont,
                repository: repositoryStyle.font,
                name: nameStyle.font,
                smallName: nameStyle.small,
                tab: tabStyle.font,
                badge: tabStyle.badge,
                interface: interfaceStyle.font(.caption),
                interfaceHeading: interfaceStyle.font(.headline),
                interfaceCode: interfaceStyle.font(.callout, monospaced: true),
                appKitHeading: interfaceStyle.appKitFont(.headline),
            )
        }

        // MARK: Private

        private var codeStyle: CodeStyle = .init()
        private var repositoryStyle: RepositoryStyle = .init()
        private var nameStyle: NameStyle = .init()
        private var tabStyle: TabStyle = .init()
        private var interfaceStyle: InterfaceStyle = .init()
    }

    private func wait(until ready: () -> Bool) async {
        for _ in 0 ..< 100 {
            if ready() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ready(), "Font preferences should update the existing view without another user action")
    }
}
