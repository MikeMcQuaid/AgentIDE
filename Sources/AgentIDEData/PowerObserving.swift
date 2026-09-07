// MARK: - PowerObserving

/// Whether the machine is running on battery, which slows safety
/// ticks that should cost nothing when they find nothing.
public protocol PowerObserving: Sendable {
    /// True on battery; false plugged in, or when the system will
    /// not say.
    var isOnBattery: Bool { get }
}

// MARK: - PluggedInPower

/// Always reports plugged in: the default for tests and for machines
/// that have no battery observer wired.
public struct PluggedInPower: PowerObserving {
    // MARK: Lifecycle

    public init() {
        // Always plugged in.
    }

    // MARK: Public

    public var isOnBattery: Bool {
        false
    }
}

#if os(macOS)
    /// Reads power state through IOKit.
    public struct IOKitPower: PowerObserving {
        // MARK: Lifecycle

        public init() {
            // Defers to PowerSource.
        }

        // MARK: Public

        public var isOnBattery: Bool {
            PowerSource.isOnBattery
        }
    }
#endif
