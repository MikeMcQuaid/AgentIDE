import AppKit
import SwiftUI

// MARK: - WindowConfigurator

/// Configures the hosting window directly: a transparent, titleless
/// titlebar over full-size content, with the standard window buttons
/// kept visible and the frame and fullscreen state persisted across
/// launches. SwiftUI's toolbar hiding removed the dead strip but
/// took the traffic lights with it; AppKit puts them back.
struct WindowConfigurator: NSViewRepresentable {
    /// Where the window is: the display it sits on and whether it
    /// fills it.
    struct Placement: Equatable {
        let displayID: CGDirectDisplayID
        let isFullScreen: Bool
    }

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

        /// The representable's callbacks, refreshed per update.
        var onVisibilityChange: ((Bool) -> Void)?
        var onPlacementChange: ((Placement) -> Void)?

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

            configureWindowIfNeeded()
            observeDisplays()
        }

        /// Configures a window not yet configured. SwiftUI updates
        /// the representable on every render, and reconfiguring
        /// re-walked the window's buttons and wrote two defaults
        /// keys per poll tick.
        func configureWindowIfNeeded() {
            guard let window, window !== configuredWindow else {
                return
            }

            configuredWindow = window
            configureWindow()
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

        /// The window already configured, so re-renders reconfigure
        /// nothing.
        private weak var configuredWindow: NSWindow?

        /// Where the window was last seen, so a screen change can
        /// tell a display that has gone from one that merely changed
        /// resolution or place, and a move that changed nothing
        /// reports nothing.
        private var lastPlacement: Placement?

        /// Whether the display the window was last seen on has gone.
        /// Screen parameters change for resolution, scaling and
        /// arrangement too, and a fullscreen space is live through
        /// all of those: only a display that is really absent earns
        /// the frame being set by hand.
        private var displayGone: Bool {
            guard let last = lastPlacement?.displayID else {
                return false
            }

            return NSScreen.screens.contains { $0.displayID == last } == false
        }

        private func configureWindow() {
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
                (NSWindow.didChangeOcclusionStateNotification, window),
            ]
            for (name, object) in names {
                observers.append(centre.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.moved(displayGone: self?.displayGone ?? false)
                        self?.reportWindowState()
                    }
                })
            }
            // A fullscreen space sent to another display posts no
            // screen-parameter change and does not always announce
            // the screen change, so the window's own move is the one
            // signal it always gives; a resize can carry a window
            // onto another display just as quietly.
            observers.append(centre.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.movedByHand() }
            })
            observers.append(centre.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberDisplay() }
            })
            reportWindowState()
        }

        /// Minimised or fully covered, the window is not being
        /// read and the poll slows.
        private func reportWindowState() {
            guard let window else {
                return
            }

            onVisibilityChange?(window.occlusionState.contains(.visible))
        }

        /// The window moved. Only fullscreen fits itself on it:
        /// fitting a dragged window would stop it being pulled past
        /// a screen edge on purpose. Every window notes where it
        /// landed.
        private func movedByHand() {
            guard window?.styleMask.contains(.fullScreen) == true else {
                rememberDisplay()
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
            }
        }

        /// Notes where the window is, and says so only when that
        /// changed.
        private func rememberDisplay() {
            guard let window, let current = window.screen?.displayID else {
                return
            }

            let placement = Placement(displayID: current, isFullScreen: window.styleMask.contains(.fullScreen))
            guard placement != lastPlacement else {
                return
            }

            lastPlacement = placement
            // Where and how the window was left, for the next run:
            // its own display, and whether it was filling it.
            let defaults = UserDefaults.standard
            defaults.set(NSScreen.uuid(of: current), forKey: Self.displayKey)
            defaults.set(placement.isFullScreen, forKey: Self.fullScreenKey)
            onPlacementChange?(placement)
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

    /// Told whether the window is visible on screen at all, so
    /// polling can slow right down while it is minimised or fully
    /// covered. Observed here because the occlusion notification is
    /// per window, and this is the one place that knows which
    /// window is ours.
    let onVisibilityChange: (Bool) -> Void

    /// Told where the window is whenever that changes: the display
    /// it landed on, and whether it is fullscreen, where the traffic
    /// lights hide and the sidebar can start higher.
    let onPlacementChange: (Placement) -> Void

    func makeNSView(context _: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ view: ConfiguringView, context _: Context) {
        view.onVisibilityChange = onVisibilityChange
        view.onPlacementChange = onPlacementChange
        view.configureWindowIfNeeded()
    }
}
