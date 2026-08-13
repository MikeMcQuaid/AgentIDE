import AgentIDEData
import AppKit

/// Tints the Dock icon for non-production flavours, so a dev build
/// is never mistaken for the installed app.
@MainActor
enum FlavourIcon {
    // MARK: Internal

    static func apply() {
        guard WorkspacePaths.isProductionBuild == false, let base = NSApp.applicationIconImage else {
            return
        }

        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.systemOrange.withAlphaComponent(Self.tintAlpha).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        NSApp.applicationIconImage = tinted
    }

    // MARK: Private

    /// Strong enough to read at Dock size, weak enough to keep the
    /// icon recognisable.
    private static let tintAlpha = 0.55
}
