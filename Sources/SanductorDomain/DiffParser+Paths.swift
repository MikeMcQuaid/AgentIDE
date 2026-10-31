extension DiffParser {
    /// Git rename headers also describe pure renames, which have no hunks.
    struct Paths {
        // MARK: Internal

        var old: String?
        var new: String?
        var renamedFrom: String?
        var sawOld = false

        mutating func consume(_ line: String) {
            if line.hasPrefix("rename from ") {
                renamedFrom = Self.unquoted(String(line.dropFirst("rename from ".count)))
                old = renamedFrom
            } else if line.hasPrefix("rename to ") {
                new = Self.unquoted(String(line.dropFirst("rename to ".count)))
            } else if line.hasPrefix("--- ") {
                sawOld = true
                old = Self.stripped(String(line.dropFirst("--- ".count)))
            } else if line.hasPrefix("+++ ") {
                new = Self.stripped(String(line.dropFirst("+++ ".count)))
            }
        }

        // MARK: Private

        private static func stripped(_ name: String) -> String? {
            let path = unquoted(name.hasSuffix("\t") ? String(name.dropLast()) : name)
            guard path != "/dev/null" else {
                return nil
            }

            return path.hasPrefix("a/") || path.hasPrefix("b/") ? String(path.dropFirst("a/".count)) : path
        }

        private static func unquoted(_ name: String) -> String {
            guard name.hasPrefix("\""), name.hasSuffix("\"") else {
                return name
            }

            var bytes = Array(name.dropFirst().dropLast().utf8)[...]
            var result = [UInt8]()
            // swiftlint:disable no_magic_numbers - Git C-quoted ASCII escapes and octal bytes.
            let escapes: [UInt8: UInt8] = [
                UInt8(ascii: "a"): 7, UInt8(ascii: "b"): 8, UInt8(ascii: "t"): 9,
                UInt8(ascii: "n"): 10, UInt8(ascii: "v"): 11, UInt8(ascii: "f"): 12, UInt8(ascii: "r"): 13,
            ]
            while let byte = bytes.popFirst() {
                guard byte == UInt8(ascii: "\\"), let escaped = bytes.popFirst() else {
                    result.append(byte)
                    continue
                }

                if (UInt8(ascii: "0") ... UInt8(ascii: "7")).contains(escaped) {
                    let remaining = bytes.prefix(2)
                    if remaining.count == 2,
                       let octal = UInt8(String(bytes: [escaped] + remaining, encoding: .utf8) ?? "", radix: 8)
                    {
                        result.append(octal)
                        bytes = bytes.dropFirst(2)
                        continue
                    }
                }
                result.append(escapes[escaped] ?? escaped)
            }
            // swiftlint:enable no_magic_numbers
            return String(bytes: result, encoding: .utf8) ?? name
        }
    }
}
