import IOKit.ps

/// Whether the machine is running on its battery, which is when a
/// safety tick that finds nothing should have cost nothing.
public enum PowerSource {
    /// True on battery; false plugged in, or on a machine with no
    /// battery, or when the system will not say.
    public static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else {
            return false
        }

        return String(providing) == kIOPSBatteryPowerValue
    }
}
