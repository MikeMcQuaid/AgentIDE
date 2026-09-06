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

        /// Set while the saved frame is being put back, so the moves
        /// that placing causes are neither recorded as the user's own
        /// nor fitted: a frame AppKit constrained on the way to the
        /// screen would otherwise be saved over the one being
        /// restored.
        private(set) var isPlacing = true

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                // Block-based observers outlive their view: the
                // centre holds the token, so one left behind keeps
                // being delivered for the life of the process.
                let centre = NotificationCenter.default
                observers.forEach(centre.removeObserver)
                observers = []
                // A window hidden for a placement this view no
                // longer lives to finish must not stay hidden.
                if pendingPlacement != nil {
                    pendingPlacement = nil
                    configuredWindow?.alphaValue = 1
                }
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

        /// The size below which a saved frame is treated as junk.
        /// Small enough to be a deliberate choice on a small
        /// screen, since a window shrunk on purpose must come back
        /// as it was left; only a frame no window could be worked
        /// in is thrown away.
        private static let minimumWidth: CGFloat = 640
        private static let minimumHeight: CGFloat = 420

        /// How long a drag or resize must pause before its frame is
        /// recorded: one defaults write per gesture rather than per
        /// pixel, and short enough that a kill loses next to nothing.
        private static let recordSeconds = 0.25

        /// Where the window was left, and how.
        private static let frameKey = "mainWindowFrame"
        private static let displayKey = "mainWindowDisplay"
        private static let fullScreenKey = "mainWindowFullScreen"

        /// Long enough for the fullscreen animation to finish before
        /// the frame is measured; the notification arrives while the
        /// window is still leaving its space.
        private static let settleSeconds = 0.6

        private var observers: [any NSObjectProtocol] = []

        /// Which recording is the latest, so an earlier one still
        /// waiting on its pause writes nothing.
        private var recordGeneration = 0

        /// The placement waiting for the window to be on a screen,
        /// run by the first notification that finds it there, or by
        /// the poll when none comes.
        private var pendingPlacement: (() -> Void)?

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
            // Only a real change of screen or fullscreen state fits
            // the window. Becoming main or being uncovered says
            // nothing about geometry, and fitting on those ran a
            // clamp at launch that beat the frame being put back.
            let fits: [(Notification.Name, Any?)] = [
                (NSApplication.didChangeScreenParametersNotification, nil),
                (NSWindow.didEnterFullScreenNotification, window),
                (NSWindow.didExitFullScreenNotification, window),
                (NSWindow.didChangeScreenNotification, window),
            ]
            for (name, object) in fits {
                observers.append(centre.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.moved(displayGone: self?.displayGone ?? false) }
                })
            }
            // These are also the first word that the window is on a
            // screen, which is what a pending placement waits for.
            for name in [NSWindow.didBecomeMainNotification, NSWindow.didChangeOcclusionStateNotification] {
                observers.append(centre.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reportWindowState()
                        self?.runPendingPlacementIfVisible()
                    }
                })
            }
            // A fullscreen space sent to another display posts no
            // screen-parameter change and does not always announce
            // the screen change, so the window's own move is the one
            // signal it always gives; a resize can carry a window
            // onto another display just as quietly.
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(centre.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.frameChanged() }
                })
            }
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

        /// The window moved or resized. Only fullscreen fits itself
        /// on it: fitting a dragged window would stop it being pulled
        /// past a screen edge on purpose. Any other window records
        /// where it is now.
        private func frameChanged() {
            guard window?.styleMask.contains(.fullScreen) == true else {
                recordFrame()
                return
            }

            moved(displayGone: false)
        }

        /// Records the frame once a drag or resize has paused. A
        /// fullscreen frame is only its screen's and never recorded.
        private func recordFrame() {
            guard isPlacing == false, let window, window.styleMask.contains(.fullScreen) == false else {
                return
            }

            rememberPlacement()
            recordGeneration += 1
            let generation = recordGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.recordSeconds) { [weak self] in
                guard let self, generation == recordGeneration, let window = self.window else {
                    return
                }
                guard window.styleMask.contains(.fullScreen) == false else {
                    return
                }

                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
            }
        }

        /// The window changed screen or fullscreen state. Fitting
        /// runs twice: entering and leaving fullscreen are animated,
        /// so the frame that needs fitting is not there yet when the
        /// notification arrives.
        private func moved(displayGone: Bool) {
            fit(displayGone: displayGone)
            rememberPlacement()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
                self?.fit(displayGone: displayGone)
                self?.rememberPlacement()
            }
        }

        /// Notes where the window is, and says so only when that
        /// changed.
        private func rememberPlacement() {
            guard isPlacing == false, let window, let current = window.screen?.displayID else {
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

        /// Puts the window back as it was left. AppKit's autosave is
        /// neither named nor read: SwiftUI holds the name, and since
        /// Monterey restoring through it brings a window left on a
        /// second display back to the main one (see the platform
        /// notes). The frame is set over whatever AppKit restored,
        /// once now so nothing shows at a default size, and again once
        /// the window is really on a screen, since a frame set before
        /// then is constrained to the main display; the window stays
        /// invisible until then rather than flash on the main display.
        /// A frame too small for three panes is thrown away, and with
        /// none the window fills the display it was left on.
        private func restoreFrame(of window: NSWindow) {
            window.setFrameAutosaveName("")
            let saved = UserDefaults.standard.string(forKey: Self.frameKey).map(NSRectFromString)
            let usable = saved.flatMap { $0.width >= Self.minimumWidth && $0.height >= Self.minimumHeight ? $0 : nil }
            if let usable {
                window.setFrame(usable, display: false)
            } else {
                fill(window)
            }
            window.alphaValue = 0
            pendingPlacement = { [weak self] in self?.place(window, at: usable) }
            // The notifications place it the moment it is drawn; the
            // poll is for a window that never says so, which is shown
            // where it is rather than left invisible, and still placed
            // if it appears later.
            whenOnScreen(window) { [weak self] onScreen in
                if onScreen {
                    self?.runPendingPlacement()
                } else {
                    window.alphaValue = 1
                }
            }
        }

        /// A visible window with no screen is placed too: its frame
        /// is off every screen, and placing is what brings it back.
        private func runPendingPlacementIfVisible() {
            guard window?.isVisible == true else {
                return
            }

            runPendingPlacement()
        }

        private func runPendingPlacement() {
            guard let pending = pendingPlacement else {
                return
            }

            pendingPlacement = nil
            pending()
        }

        /// Puts the window where it was left, now that it is really
        /// on a screen: the saved frame, or filling the display it
        /// was left on when there is none, then shows it, then
        /// fullscreen when it was closed that way, in that order,
        /// since a window in a fullscreen space must never be moved.
        /// A frame left on a display that has gone is brought onto
        /// one that exists. Only from here on are its moves recorded
        /// and its placement reported.
        private func place(_ window: NSWindow, at frame: NSRect?) {
            if let frame {
                window.setFrame(frame, display: true)
            }
            move(window, ontoDisplay: UserDefaults.standard.string(forKey: Self.displayKey))
            if frame == nil {
                fill(window)
            }
            if window.screen == nil {
                fitToScreen()
            }
            window.alphaValue = 1
            isPlacing = false
            rememberPlacement()
            if UserDefaults.standard.bool(forKey: Self.fullScreenKey) {
                enterFullScreen(window)
            }
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
