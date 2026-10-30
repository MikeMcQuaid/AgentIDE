/// Dotted tool versions compared as numbers, component by component,
/// so `0.153.4` is newer than `0.152.1` and than `0.153`.
public enum ToolVersion {
    // MARK: Public

    /// Whether the first version is older than the second. Anything
    /// that does not read as numbers compares as text, which is
    /// wrong only for versions no tool here has ever printed.
    public static func isOlder(_ version: String, than other: String) -> Bool {
        let lhs = components(of: version)
        let rhs = components(of: other)
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right
        }
        return lhs.count < rhs.count
    }

    // MARK: Private

    private static func components(of version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
