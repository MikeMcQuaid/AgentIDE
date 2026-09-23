/// What a pull request's checks add up to. Split from the client
/// body for length.
extension GitHubClient {
    /// The rollup, the failures it counts and the failures it does
    /// not.
    struct Rollup {
        let checks: String
        let failingLinks: [String]
        let optionalFailures: Int
    }

    /// The rollup over the checks that decide it. With required
    /// checks named, only those count: a failing check nobody
    /// requires leaves the rollup green and is neither opened nor
    /// copied, only counted for the help, and a required one GitHub
    /// has yet to hear from keeps it pending, which is what GitHub's
    /// own merge box says. Without any, every check counts.
    static func rollup(_ rows: [CheckRow], required: Set<String>) -> Rollup {
        let counted = required.isEmpty ? rows : rows.filter { required.contains($0.name ?? $0.context ?? "") }
        let unreported = required.subtracting(counted.compactMap { $0.name ?? $0.context })
        let states = counted.map(Self.state) + Array(repeating: "PENDING", count: unreported.count)
        let failing = counted.filter { Self.isFailure(Self.state($0)) }
        return Rollup(
            checks: Self.aggregate(states),
            failingLinks: failing.compactMap(\.detailsUrl), // swiftformat:disable:this acronyms
            optionalFailures: rows.count { Self.isFailure(Self.state($0)) } - failing.count,
        )
    }

    private static func state(_ row: CheckRow) -> String {
        (row.conclusion ?? row.state ?? "").uppercased()
    }

    /// A check run fails with `FAILURE`, a status context with
    /// `ERROR` too: one predicate, so what turns the rollup red is
    /// what is offered to open and what is counted.
    private static func isFailure(_ state: String) -> Bool {
        state == "FAILURE" || state == "ERROR"
    }

    private static func aggregate(_ states: [String]) -> String {
        guard states.isEmpty == false else {
            return ""
        }

        if states.contains(where: isFailure) {
            return "FAILURE"
        }
        if states.allSatisfy({ $0 == "SUCCESS" || $0 == "NEUTRAL" || $0 == "SKIPPED" }) {
            return "SUCCESS"
        }
        return "PENDING"
    }
}
