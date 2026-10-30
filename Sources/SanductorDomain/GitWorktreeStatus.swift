/// A local Git reading shared by the desktop and SSH sidebar.
public struct GitWorktreeStatus: Hashable, Sendable {
    // MARK: Lifecycle

    public init(branch: String?, isDirty: Bool, aheadOfUpstream: Int?, behindUpstream: Int?) {
        self.branch = branch
        self.isDirty = isDirty
        self.aheadOfUpstream = aheadOfUpstream
        self.behindUpstream = behindUpstream
    }

    /// NUL-delimited porcelain keeps unusual filenames out of the headers.
    public init(porcelain: String) {
        var branchName: String?
        var ahead: Int?
        var behind: Int?
        var dirty = false
        var records = porcelain.split(separator: "\0").makeIterator()
        while let record = records.next() {
            if record.hasPrefix("# branch.head ") {
                let name = String(record.dropFirst("# branch.head ".count))
                branchName = name == "(detached)" ? nil : name
            } else if record.hasPrefix("# branch.ab ") {
                let counts = record.dropFirst("# branch.ab ".count).split(separator: " ")
                ahead = counts.first.flatMap { Int($0.dropFirst()) }
                behind = counts.dropFirst().first.flatMap { Int($0.dropFirst()) }
            } else if let kind = record.first, "12u?".contains(kind) {
                dirty = true
                if kind == "2" {
                    _ = records.next()
                }
            }
        }
        self.init(branch: branchName, isDirty: dirty, aheadOfUpstream: ahead, behindUpstream: behind)
    }

    // MARK: Public

    public static let arguments = ["status", "--porcelain=v2", "-z", "--no-renames"]
    public static let countsHelp = "↑ commits not yet pushed, ↓ commits not yet pulled, ± uncommitted changes"

    public let branch: String?
    public let isDirty: Bool
    public let aheadOfUpstream: Int?
    public let behindUpstream: Int?

    public var summary: String {
        var parts = [String]()
        if let aheadOfUpstream, aheadOfUpstream > 0 {
            parts.append("↑" + String(aheadOfUpstream))
        }
        if let behindUpstream, behindUpstream > 0 {
            parts.append("↓" + String(behindUpstream))
        }
        if isDirty {
            parts.append("±")
        }
        return parts.joined(separator: " ")
    }
}
