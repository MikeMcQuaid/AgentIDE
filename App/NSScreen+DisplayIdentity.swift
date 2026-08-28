import AppKit

/// Display identity for window placement, used by the window
/// configurator; its own file for that file's length.
extension NSScreen {
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
