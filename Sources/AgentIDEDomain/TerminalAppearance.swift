/// The palette a terminal pane draws with. Agent panes pin the one
/// their session launched under, since agent TUIs read the
/// terminal's colours once at startup and trust them forever.
/// Not raw-value backed: the formatter strips a raw value equal to
/// its case name while the linter demands one, so the metadata
/// string is mapped by hand where it is stored.
public enum TerminalAppearance: Sendable {
    case dark
    case light
}
