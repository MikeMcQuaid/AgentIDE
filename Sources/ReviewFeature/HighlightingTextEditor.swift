import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

// NSTextView ranges are UTF-16 offsets, so NSString and
// NSAttributedString are the correct arithmetic here, not String.
// swiftlint:disable legacy_objc_type

// MARK: - HighlightingTextEditor

/// A code editor: monospaced NSTextView with syntax highlighting,
/// a line-number ruler, visible invisibles and an optional line to
/// jump to when it first appears.
struct HighlightingTextEditor: NSViewRepresentable {
    // MARK: Internal

    final class Coordinator: NSObject, NSTextViewDelegate {
        // MARK: Lifecycle

        init(text: Binding<String>, language: SyntaxLanguage?) {
            self.text = text
            self.language = language
        }

        // Isolated: the observer tokens are main-actor state, and
        // AppKit releases coordinators on the main thread anyway.
        isolated deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        // MARK: Internal

        var text: Binding<String>
        let language: SyntaxLanguage?
        var didJump = false

        static func highlight(_ view: NSTextView, language: SyntaxLanguage?) {
            guard let language, let storage = view.textStorage else {
                return
            }

            let selection = view.selectedRanges
            let content = view.string as NSString
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: content.length))
            storage.addAttribute(
                .foregroundColor,
                value: NSColor.textColor,
                range: NSRange(location: 0, length: content.length),
            )
            // One backend for every surface: the same engine the diff
            // uses classifies the whole document here.
            let ranges = CodeHighlighter.documentRanges(in: view.string, language: language)
            for (range, kind) in ranges where NSMaxRange(range) <= content.length {
                storage.addAttribute(.foregroundColor, value: colour(for: kind), range: range)
            }
            storage.endEditing()
            view.selectedRanges = selection
        }

        /// Watches for the window changing screens and the display
        /// arrangement changing: either can leave the scroll view on
        /// the old screen's geometry while SwiftUI's chrome lays out
        /// correctly, the editor's text then bleeding across the
        /// window under its neighbours.
        func watchDisplayChanges(of scroll: NSScrollView) {
            scrollView = scroll
            let names: [Notification.Name] = [
                NSWindow.didChangeScreenNotification,
                NSApplication.didChangeScreenParametersNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main,
                ) { [weak self] _ in
                    // A turn later, once the switch's own layout has
                    // settled; the explicit isolation is what lets
                    // the snap touch AppKit frames.
                    Task { @MainActor in
                        self?.realignAfterDisplayChange()
                    }
                })
            }
        }

        /// Snaps the scroll view back onto its hosting container,
        /// SwiftUI's own view and therefore the truth about where
        /// the editor belongs; frames already agreeing make this a
        /// no-op, so a healthy layout is never disturbed.
        func realignAfterDisplayChange() {
            guard let scroll = scrollView, let container = scroll.superview,
                  scroll.frame != container.bounds
            else {
                return
            }

            scroll.frame = container.bounds
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = view.string
            Self.highlight(view, language: language)
        }

        // MARK: Private

        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []

        private static func colour(for kind: SyntaxToken.Kind) -> NSColor {
            switch kind {
            case .keyword:
                .systemPurple

            case .string:
                .systemRed

            case .comment:
                .systemGreen

            case .number:
                .systemBlue

            case .plain:
                .textColor
            }
        }
    }

    @Binding var text: String

    let language: SyntaxLanguage?
    let jumpToLine: Int?
    var changedLines: Set<Int> = []

    /// What the file's `.editorconfig` says: the indentation Tab
    /// inserts and the width tabs render at.
    var settings: EditorConfigSettings = .init()

    func makeNSView(context: Context) -> NSScrollView {
        // A hand-built text stack, because the layout manager draws
        // whitespace itself in the shared light tone the diff uses.
        let storage = NSTextStorage()
        let layoutManager = WhitespaceLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = EditingTextView(frame: .zero, textContainer: container)
        view.language = language
        view.configuredIndentUnit = settings.indentUnit
        view.autoresizingMask = .width
        view.isVerticallyResizable = true
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.font = CodeStyle.nsFont
        view.isRichText = false
        view.allowsUndo = true
        // Code is not prose: smart quotes, dashes, replacements and
        // corrections all silently break what is typed here.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        // The find bar is AppKit's own, so Cmd-F, Cmd-G and
        // Cmd-Shift-G work here exactly as they do everywhere else.
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.string = text
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = view
        scroll.hasVerticalRuler = true
        let ruler = LineNumberRuler(textView: view)
        ruler.changedLines = changedLines
        scroll.verticalRulerView = ruler
        scroll.rulersVisible = true
        Coordinator.highlight(view, language: language)
        context.coordinator.watchDisplayChanges(of: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else {
            return
        }

        // The configuration lands after the file, since it is read
        // off the view while the text is already on screen.
        if let editing = view as? EditingTextView {
            editing.configuredIndentUnit = settings.indentUnit
            editing.applyTabWidth(settings.tabWidth ?? settings.indentSize)
        }
        if view.string != text {
            view.string = text
            Coordinator.highlight(view, language: language)
        }
        if let jumpToLine, context.coordinator.didJump == false {
            context.coordinator.didJump = true
            jump(to: jumpToLine, in: view)
        }
        if let ruler = scroll.verticalRulerView as? LineNumberRuler {
            ruler.changedLines = changedLines
        }
        scroll.verticalRulerView?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language)
    }

    // MARK: Private

    /// Scrolls to and selects a one-based line.
    private func jump(to line: Int, in view: NSTextView) {
        let lines = view.string.split(separator: "\n", omittingEmptySubsequences: false)
        let previous = lines.prefix(max(0, line - 1))
        let location = previous.reduce(0) { $0 + ($1 as NSString).length + 1 }
        let length = line <= lines.count ? (String(lines[line - 1]) as NSString).length : 0
        let range = NSRange(location: min(location, (view.string as NSString).length), length: length)
        view.scrollRangeToVisible(range)
        view.setSelectedRange(range)
    }
}

// MARK: - WhitespaceLayoutManager

/// Draws spaces and tabs as visible glyphs in the shared light
/// whitespace tone, matching the review diff. Nonisolated to match
/// `NSLayoutManager`, which AppKit drives itself on the main thread.
private final nonisolated class WhitespaceLayoutManager: NSLayoutManager {
    // MARK: Lifecycle

    deinit {
        // Nothing to clean up.
    }

    // MARK: Internal

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else {
            return
        }

        let text = storage.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CodeStyle.nsFont,
            .foregroundColor: CodeStyle.whitespaceNSColour,
        ]
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for index in characters.location ..< NSMaxRange(characters) {
            let symbol: String? =
                switch text.character(at: index) {
                case Self.space:
                    "·"

                case Self.tab:
                    "⇥"

                default:
                    nil
                }
            guard let symbol else {
                continue
            }

            let glyphIndex = glyphIndexForCharacter(at: index)
            let fragment = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let position = location(forGlyphAt: glyphIndex)
            let point = NSPoint(x: origin.x + fragment.minX + position.x, y: origin.y + fragment.minY)
            NSAttributedString(string: symbol, attributes: attributes).draw(at: point)
        }
    }

    // MARK: Private

    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09
}

// swiftlint:enable legacy_objc_type
