import AppKit
import SwiftUI

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
        }

        // MARK: Private

        private static let autosaveName = "AgentIDEMainWindow"

        /// Long enough for the fullscreen animation to finish before
        /// the frame is measured; the notification arrives while the
        /// window is still leaving its space.
        private static let settleSeconds = 0.6

        private var observers: [any NSObjectProtocol] = []

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
                (NSWindow.didEnterFullScreenNotification, window),
                (NSWindow.didExitFullScreenNotification, window),
                (NSWindow.didChangeScreenNotification, window),
            ]
            for (name, object) in names {
                observers.append(centre.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.moved() }
                })
            }
        }

        /// The window changed screen or fullscreen state. Fitting
        /// runs twice: entering and leaving fullscreen are animated,
        /// so the frame that needs fitting is not there yet when the
        /// notification arrives.
        private func moved() {
            fit()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
                self?.fit()
            }
        }

        private func fit() {
            guard let window else {
                return
            }

            if window.styleMask.contains(.fullScreen) {
                fitFullScreen(of: window)
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
        private func fitFullScreen(of window: NSWindow) {
            guard let screen = window.screen else {
                // No screen at all to fit: leaving fullscreen puts
                // the window back on one that exists.
                window.toggleFullScreen(nil)
                return
            }
            guard window.frame != screen.frame else {
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

        /// The frame autosave restores position and size. Fullscreen
        /// deliberately does not restore: macOS reopens fullscreen
        /// spaces on the display it chooses (often the one with the
        /// Dock), so the window restores as a plain frame the user
        /// can drag to a monitor before going fullscreen.
        private func restoreFrame(of window: NSWindow) {
            if window.frameAutosaveName != Self.autosaveName {
                window.setFrameAutosaveName(Self.autosaveName)
            }
        }
    }

    func makeNSView(context _: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ view: ConfiguringView, context _: Context) {
        view.configureWindow()
    }
}
