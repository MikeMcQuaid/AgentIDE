import SwiftTerm

/// Modifier encoding for the phone's fixed set of terminal keys.
enum MobileTerminalKeys {
    // MARK: Internal

    static func modified(_ bytes: [UInt8], shift: Bool, control: Bool) -> [UInt8] {
        guard shift || control else {
            return bytes
        }

        if bytes == EscapeSequences.cmdTab, shift {
            return EscapeSequences.cmdBackTab
        }
        guard bytes.first == escape, bytes.count > introducerLength, let final = bytes.last else {
            return bytes
        }

        let parameter = 1 + (shift ? 1 : 0) + (control ? controlMask : 0)
        let prefix = final == UInt8(ascii: "~")
            ? String(bytes: bytes.dropFirst(introducerLength).dropLast(), encoding: .utf8) ?? "1" : "1"
        return Array(("\u{1B}[" + prefix + ";" + String(parameter)).utf8) + [final]
    }

    // MARK: Private

    private static let introducerLength = 2
    private static let escape: UInt8 = 0x1B
    private static let controlMask = 4
}
