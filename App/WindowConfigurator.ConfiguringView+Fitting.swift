import AppKit

/// Getting the window onto its screen and fitting it there, used by
/// the window configurator; its own file for that file's length.
extension WindowConfigurator.ConfiguringView {
    /// The margin left around a window filling its screen, and what
    /// centring divides by.
    private static let screenInset: CGFloat = 8
    private static let halves: CGFloat = 2

    /// How long the window gets to appear before a saved frame or a
    /// remembered fullscreen is given up on: a fifth of a second at
    /// a time, for a couple of seconds.
    private static let readyAttempts = 20
    private static let readySeconds = 0.2

    /// Fills whichever screen the window is on, less a margin: a
    /// fixed default is either too big for a laptop or too small
    /// for a desk.
    func fill(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        window.setFrame(visible.insetBy(dx: Self.screenInset, dy: Self.screenInset), display: true)
    }

    /// Lays the window out for the screen it is on: a fullscreen
    /// window to the display it lost, any other back inside its
    /// screen's edges.
    func fit(displayGone: Bool) {
        guard let window else {
            return
        }

        if window.styleMask.contains(.fullScreen) {
            fitFullScreen(of: window, hasLostDisplay: displayGone)
        } else if isPlacing == false {
            // Not while the saved frame is still being put back: the
            // frame that wants fitting is not there yet.
            fitToScreen()
        }
        // The space a fullscreen window lands on paints black
        // behind it; a window that fitted itself into one must
        // ask for the redraw that the move itself never did.
        window.viewsNeedDisplay = true
        window.displayIfNeeded()
    }

    /// A fullscreen window keeps the size of the display it was
    /// on when that display goes. macOS moves the space to a
    /// screen that exists, but the content stays drawn to the
    /// old, larger frame: what shows is the black behind it.
    /// Only the display the window was on going away is fitted
    /// by hand: AppKit owns the frame of a window in a
    /// fullscreen space, and setting it while a space merely
    /// moved between two live displays left both screens black
    /// until the app was killed, which a resolution, scaling or
    /// arrangement change must not be able to reproduce. Every
    /// other change lays the content out again for the size
    /// AppKit gave it, and nothing more.
    private func fitFullScreen(of window: NSWindow, hasLostDisplay: Bool) {
        guard let screen = window.screen else {
            // No screen at all to fit: leaving fullscreen puts
            // the window back on one that exists.
            window.toggleFullScreen(nil)
            return
        }
        guard hasLostDisplay, window.frame != screen.frame else {
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            return
        }

        window.setFrame(screen.frame, display: true, animate: false)
    }

    /// Brings the frame back inside the screen it is on, keeping
    /// its size where it fits and its corner where it can.
    private func fitToScreen() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        guard frame != window.frame else {
            return
        }

        window.setFrame(frame, display: true, animate: false)
    }

    /// Centres the window on the display it was left on, named by
    /// that display's own identity since numbers move, when it has
    /// come back anywhere else.
    func move(_ window: NSWindow, ontoDisplay name: String?) {
        let screen = name.flatMap { name in
            NSScreen.screens.first { $0.displayID.map(NSScreen.uuid(of:)) == name }
        }
        guard let screen, screen.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) == false else {
            return
        }

        window.setFrameOrigin(CGPoint(
            x: screen.visibleFrame.midX - window.frame.width / Self.halves,
            y: screen.visibleFrame.midY - window.frame.height / Self.halves,
        ))
    }

    /// Goes fullscreen once the window is really on a screen:
    /// AppKit drops the toggle on a window it has not shown yet.
    func enterFullScreen(_ window: NSWindow) {
        guard window.styleMask.contains(.fullScreen) == false else {
            return
        }

        whenOnScreen(window) { onScreen in
            if onScreen {
                window.toggleFullScreen(nil)
            }
        }
    }

    /// Calls back once the window is visible and on a screen, a
    /// fifth of a second at a time for a couple of seconds, and
    /// with `false` when it never appeared.
    func whenOnScreen(
        _ window: NSWindow,
        attempts: Int = WindowConfigurator.ConfiguringView.readyAttempts,
        then act: @escaping (Bool) -> Void,
    ) {
        if window.isVisible, window.screen != nil {
            act(true)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.readySeconds) { [weak self] in
                self?.whenOnScreen(window, attempts: attempts - 1, then: act)
            }
        } else {
            act(false)
        }
    }
}
