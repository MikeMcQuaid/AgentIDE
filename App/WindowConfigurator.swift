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
            // Nothing to clean up.
        }

        // MARK: Internal

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
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
        private static let fullscreenKey = "windowFullscreen"
        private static let fullscreenScreenKey = "windowFullscreenScreen"

        private var restoredFullscreen = false
        private var observers: [NSObjectProtocol] = []

        /// The frame autosave restores position and size; fullscreen
        /// does not round-trip through it, so its state persists via
        /// the enter and exit notifications and replays once, moving
        /// the window onto the remembered screen first so fullscreen
        /// returns to the monitor it was on.
        private func restoreFrame(of window: NSWindow) {
            if window.frameAutosaveName != Self.autosaveName {
                window.setFrameAutosaveName(Self.autosaveName)
            }
            observeFullscreen(of: window)
            if restoredFullscreen == false {
                restoredFullscreen = true
                if UserDefaults.standard.bool(forKey: Self.fullscreenKey),
                   window.styleMask.contains(.fullScreen) == false {
                    moveToRememberedScreen(window)
                    window.toggleFullScreen(nil)
                }
            }
        }

        private func moveToRememberedScreen(_ window: NSWindow) {
            guard let stored = UserDefaults.standard.string(forKey: Self.fullscreenScreenKey),
                  let screen = NSScreen.screens.first(where: { NSStringFromRect($0.frame) == stored }),
                  window.screen != screen
            else {
                return
            }

            window.setFrameOrigin(screen.visibleFrame.origin)
        }

        private func observeFullscreen(of window: NSWindow) {
            guard observers.isEmpty else {
                return
            }

            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main,
            ) { [weak window] _ in
                UserDefaults.standard.set(true, forKey: Self.fullscreenKey)
                if let frame = window?.screen?.frame {
                    UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.fullscreenScreenKey)
                }
            })
            observers.append(center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main,
            ) { _ in
                UserDefaults.standard.set(false, forKey: Self.fullscreenKey)
            })
        }
    }

    func makeNSView(context _: Context) -> ConfiguringView {
        ConfiguringView()
    }

    func updateNSView(_ view: ConfiguringView, context _: Context) {
        view.configureWindow()
    }
}
