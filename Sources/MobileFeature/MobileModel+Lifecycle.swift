public extension MobileModel {
    /// Preserves established connections while iOS permits them to live.
    func suspend() {
        if isConnected == false {
            deactivate()
        }
    }
}
