@testable import PRFeature
import SanductorDomain
import Testing

struct PullRequestCheckFilterTests {
    @Test(arguments: [false, true], [false, true])
    func `requirement and progress filters combine`(required: Bool, unfinished: Bool) {
        let checks = [PullRequestCheck.Requirement.required, .optional, .unknown].flatMap { requirement in
            ["COMPLETED", "IN_PROGRESS", "EXPECTED"].map { status in
                PullRequestCheck(
                    name: requirement.rawValue + status, status: status, conclusion: "", requirement: requirement,
                )
            }
        }
        let filter = PullRequestCheckFilter(requiredOnly: required, unfinishedOnly: unfinished)
        let matches = checks.filter(filter.includes)
        #expect(matches.count == (required ? 1 : 3) * (unfinished ? 2 : 3))
        if required {
            #expect(matches.allSatisfy { $0.requirement == .required })
        }
        if unfinished {
            #expect(matches.allSatisfy { $0.isComplete == false })
        }
    }
}
