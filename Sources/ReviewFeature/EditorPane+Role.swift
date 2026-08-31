public extension EditorPane {
    /// The slot an editor pane fills. Each slot keeps its own finder
    /// and open file under key-suffixed defaults, so two mounted
    /// editors never answer one request twice; the window routes
    /// requests between them by these names. Split from the pane
    /// for length.
    enum Role: String, CaseIterable, Sendable {
        // The case names are the persisted key suffixes (SwiftFormat
        // strips explicit raw values); keep names stable or migrate
        // deliberately. Centre first: a file open in both slots
        // routes to the visible centre before the side.
        // swiftlint:disable explicit_enum_raw_value
        case centre
        case utility

        // MARK: Public

        /// The other slot, where a moved file lands.
        public var other: Self {
            if self == .centre {
                .utility
            } else {
                .centre
            }
        }

        // swiftlint:enable explicit_enum_raw_value

        /// The slot's defaults key for one of the shared base names.
        public func key(_ base: String) -> String {
            base + "." + rawValue
        }
    }
}
