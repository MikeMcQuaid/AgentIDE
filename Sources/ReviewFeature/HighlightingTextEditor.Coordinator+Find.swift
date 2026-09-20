import AppKit

extension HighlightingTextEditor.Coordinator {
    // MARK: Internal

    func watchFindChanges(of scroll: NSScrollView) {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self, weak scroll] notification in
            guard let field = notification.object as? NSSearchField else {
                return
            }

            MainActor.assumeIsolated {
                if let scroll {
                    self?.findChanged(field, in: scroll)
                }
            }
        })
    }

    // MARK: Private

    private static let findSettlingMilliseconds = 150

    private func findChanged(_ field: NSSearchField, in scroll: NSScrollView) {
        guard let bar = scroll.findBarView, field.isDescendant(of: bar),
              let view = scroll.documentView as? NSTextView
        else {
            return
        }

        findTask?.cancel()
        guard field.stringValue.isEmpty == false else {
            return
        }

        let selection = view.selectedRanges
        findTask = Task { [weak scroll, weak field, weak view] in
            try? await Task.sleep(for: .milliseconds(Self.findSettlingMilliseconds))
            guard Task.isCancelled == false,
                  let scroll, scroll.isFindBarVisible, let window = unsafe scroll.window,
                  let field, let editor = field.currentEditor(),
                  let view, view.isHiddenOrHasHiddenAncestor == false,
                  view.selectedRanges == selection
            else {
                return
            }

            let querySelection = editor.selectedRange
            // AppKit's find action needs its document to be
            // first responder; return focus before drawing.
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 0, length: 0))
            let action = NSMenuItem()
            action.tag = NSTextFinder.Action.nextMatch.rawValue
            view.performTextFinderAction(action)
            if view.selectedRange().length == 0 {
                view.selectedRanges = selection
            }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = querySelection
        }
    }
}
