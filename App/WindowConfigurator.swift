import AppKit
import SwiftUI
import TerminalUI

// MARK: - WindowConfigurator

/// Configures the hosting window directly: a transparent, titleless
/// titlebar over full-size content, with the standard window buttons
/// kept visible and the frame and fullscreen state persisted across
/// launches. SwiftUI's toolbar hiding removed the dead strip but
/// took the traffic lights with it; AppKit puts them back.
struct WindowConfigurator: NSViewRepresentable {
    /// A zero-sized view that configures whatever window hosts it.
    final class ConfiguringView: NSView {
        // MARK: Lifecycle

        deinit {
            // The observers go when the view leaves its window,
            // which AppKit always tells it about; a deinit cannot
            // touch them, since Swift will not let one reach
            // non-Sendable state.
        }

        // MARK: Internal

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                // Block-based observers outlive their view: the
                // centre holds the token, so one left behind keeps
                // being delivered for the life of the process.
                let centre = NotificationCenter.default
                observers.forEach(centre.removeObserver)
                observers = []
                return
            }

            configureWindow()
            observeDisplays()
        }

        func configureWindow() {
            guard let window else {
                return
            }

            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // An empty toolbar still reserves a tall unified strip;
            // removing it leaves only the plain titlebar, which the
            // panes draw beneath.
            if window.toolbar != nil {
                window.toolbar = nil
            }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = false
            }
            restoreFrame(of: window)
            rememberDisplay()
        }

        // MARK: Private

        private static let autosaveName = "AgentIDEMainWindow"

        /// The size below which a saved frame is treated as junk.
        /// Small enough to be a deliberate choice on a small
        /// screen, since a window shrunk on purpose must come back
        /// as it was left; only a frame no window could be worked
        /// in is thrown away.
        private static let minimumWidth: CGFloat = 640
        private static let minimumHeight: CGFloat = 420

        /// How long the window gets to appear before a remembered
        /// fullscreen is given up on: a fifth of a second at a time,
        /// for a couple of seconds.
        private static let readyAttempts = 20
        private static let readySeconds = 0.2

        /// The margin left around a window filling its screen, and
        /// what centring divides by.
        private static let screenInset: CGFloat = 8
        private static let halves: CGFloat = 2

        /// Where the window was left, and how.
        private static let displayKey = "mainWindowDisplay"
        private static let fullScreenKey = "mainWindowFullScreen"

        /// Long enough for the fullscreen animation to finish before
        /// the frame is measured; the notification arrives while the
        /// window is still leaving its space.
        private static let settleSeconds = 0.6

        private var observers: [any NSObjectProtocol] = []

        /// The last reported mismatch, so a window that stays wrong
        /// says so once rather than on every move.
        private var lastMismatch: String?

        /// The display the window was last seen on, so a screen
        /// change can tell one that has gone from one that merely
        /// changed resolution or place.
        private var lastDisplayID: CGDirectDisplayID?

        /// Whether the display the window was last seen on has gone.
        /// Screen parameters change for resolution, scaling and
        /// arrangement too, and a fullscreen space is live through
        /// all of those: only a display that is really absent earns
        /// the frame being set by hand.
        private var displayGone: Bool {
            guard let last = lastDisplayID else {
                return false
            }

            return NSScreen.screens.contains { $0.displayID == last } == false
        }

        /// Displays come and go. Unplugging the one a fullscreen
        /// window is on leaves the window black on a space with no
        /// screen behind it, and coming out of fullscreen restores
        /// the frame it had on the display that has gone: wider than
        /// the remaining screen, so its edges cannot be dragged and
        /// its green button cannot fill a screen it does not fit.
        /// Both are handled here rather than left to the user.
        private func observeDisplays() {
            guard observers.isEmpty, let window else {
                return
            }

            let centre = NotificationCenter.default
            let names: [(Notification.Name, Any?)] = [
                (NSApplication.didChangeScreenParametersNotification, nil),
                (NSWindow.didBecomeMainNotification, window),
                (NSWindow.didEnterFullScreenNotification, window),
                (NSWindow.didExitFullScreenNotification, window),
                (NSWindow.didChangeScreenNotification, window),
            ]
            for (name, object) in names {
                observers.append(centre.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.moved(displayGone: self?.displayGone ?? false) }
                })
            }
            // A fullscreen space sent to another display posts no
            // screen-parameter change and does not always announce
            // the screen change, so the window's own move is the one
            // signal it always gives. Only fullscreen acts on it:
            // fitting a dragged window would stop it being pulled
            // past a screen edge on purpose.
            observers.append(centre.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.movedIfFullScreen() }
            })
        }

        private func movedIfFullScreen() {
            guard window?.styleMask.contains(.fullScreen) == true else {
                return
            }

            moved(displayGone: false)
        }

        /// The window changed screen or fullscreen state. Fitting
        /// runs twice: entering and leaving fullscreen are animated,
        /// so the frame that needs fitting is not there yet when the
        /// notification arrives.
        private func moved(displayGone: Bool) {
            fit(displayGone: displayGone)
            rememberDisplay()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
                self?.fit(displayGone: displayGone)
                self?.rememberDisplay()
                self?.reportUnfittedFullScreen()
            }
        }

        private func rememberDisplay() {
            guard let current = window?.screen?.displayID else {
                return
            }

            lastDisplayID = current
            // Where and how the window was left, for the next run:
            // its own display, and whether it was filling it.
            let defaults = UserDefaults.standard
            defaults.set(NSScreen.uuid(of: current), forKey: Self.displayKey)
            defaults.set(window?.styleMask.contains(.fullScreen) == true, forKey: Self.fullScreenKey)
        }

        /// Fills whichever screen the window is on, less a margin: a
        /// fixed default is either too big for a laptop or too small
        /// for a desk.
        private func fill(_ window: NSWindow) {
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
                return
            }

            window.setFrame(visible.insetBy(dx: Self.screenInset, dy: Self.screenInset), display: true)
        }

        /// Puts the window back where it was left: the same display,
        /// and fullscreen again when that is how it was closed. The
        /// frame is placed before any toggle, since a window in a
        /// fullscreen space must never be moved.
        private func restorePlacement(of window: NSWindow) {
            let defaults = UserDefaults.standard
            let saved = defaults.string(forKey: Self.displayKey)
            let screen = saved.flatMap { name in
                NSScreen.screens.first { $0.displayID.map(NSScreen.uuid(of:)) == name }
            }
            if let screen, screen.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) == false {
                window.setFrameOrigin(CGPoint(
                    x: screen.visibleFrame.midX - window.frame.width / Self.halves,
                    y: screen.visibleFrame.midY - window.frame.height / Self.halves,
                ))
            }
            guard defaults.bool(forKey: Self.fullScreenKey) else {
                return
            }

            enterFullScreen(window)
        }

        /// Goes fullscreen once the window is really on a screen.
        /// AppKit drops the toggle on a window it has not shown yet,
        /// which is exactly where this runs from, so it waits for
        /// one rather than asking once and hoping.
        private func enterFullScreen(_ window: NSWindow, attempts: Int = ConfiguringView.readyAttempts) {
            guard window.styleMask.contains(.fullScreen) == false else {
                return
            }
            guard window.isVisible, window.screen != nil else {
                guard attempts > 0 else {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + Self.readySeconds) { [weak self] in
                    self?.enterFullScreen(window, attempts: attempts - 1)
                }
                return
            }

            window.toggleFullScreen(nil)
        }

        private func fit(displayGone: Bool) {
            guard let window else {
                return
            }

            if window.styleMask.contains(.fullScreen) {
                fitFullScreen(of: window, hasLostDisplay: displayGone)
            } else {
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

        /// Says once, in Messages, when a settled fullscreen window
        /// still does not match the screen it is on: the frame AppKit
        /// left behind is the fact needed to fix a window that has to
        /// be toggled out of fullscreen by hand, and it cannot be
        /// read from outside the app. A fullscreen window that keeps
        /// the menu bar fills the screen's visible frame rather than
        /// its whole frame, which is correct and said nothing worth
        /// reading.
        private func reportUnfittedFullScreen() {
            guard let window, window.styleMask.contains(.fullScreen), let screen = window.screen,
                  window.frame != screen.frame, window.frame != screen.visibleFrame
            else {
                return
            }

            let mismatch = "Fullscreen window is " + NSStringFromRect(window.frame)
                + " on a screen of " + NSStringFromRect(screen.frame)
            guard mismatch != lastMismatch else {
                return
            }

            lastMismatch = mismatch
            ErrorLog.shared.note(mismatch)
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

        /// Puts the window back as it was left: the autosaved frame
        /// applied rather than merely named, on the display it was
        /// closed on, fullscreen again when it was closed that way,
        /// and filling whichever screen it lands on when there is
        /// nothing saved or what was saved is too small for three
        /// panes. macOS reopens a fullscreen space on the display it
        /// chooses, which is why the display is remembered by its
        /// own identity and the window placed before any toggle.
        private func restoreFrame(of window: NSWindow) {
            guard window.frameAutosaveName != Self.autosaveName else {
                return
            }

            window.setFrameAutosaveName(Self.autosaveName)
            // Naming the autosave does not apply it: without this the
            // window opens at whatever size its content asked for,
            // which changed the moment the sidebar started painting
            // from cache. A frame too small for the panes is grown to
            // the default rather than restored as saved.
            if window.setFrameUsingName(Self.autosaveName) {
                let minimum = NSSize(width: Self.minimumWidth, height: Self.minimumHeight)
                if window.frame.width < minimum.width || window.frame.height < minimum.height {
                    fill(window)
                }
                restorePlacement(of: window)
                return
            }

            fill(window)
            restorePlacement(of: window)
        }
    }

    func makeNSView(context _: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ view: ConfiguringView, context _: Context) {
        view.configureWindow()
    }
}

// MARK: - NSScreen display identity

private extension NSScreen {
    /// The display's own identity, which outlives its number across
    /// reboots and rearrangements.
    static func uuid(of display: CGDirectDisplayID) -> String? {
        guard let identity = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else {
            return nil
        }

        return CFUUIDCreateString(nil, identity) as String?
    }

    /// The display this screen renders on, which outlives the
    /// `NSScreen` object a reconfiguration replaces.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int)
            .map(CGDirectDisplayID.init)
    }
}
