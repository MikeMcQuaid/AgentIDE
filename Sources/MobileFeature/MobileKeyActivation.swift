/// Shares touch-down delivery with semantic button activation without sending twice.
final class MobileKeyActivation {
    // MARK: Lifecycle

    init(action: @escaping (_ held: Bool) -> Void) {
        self.action = action
    }

    deinit { /* No resources to release. */ }

    // MARK: Internal

    func touchDown() {
        sentOnTouchDown = true
        action(true)
    }

    func activate() {
        guard sentOnTouchDown == false else {
            sentOnTouchDown = false
            return
        }

        action(false)
    }

    func cancelTouch() {
        sentOnTouchDown = false
    }

    // MARK: Private

    private let action: (_ held: Bool) -> Void
    private var sentOnTouchDown = false
}
