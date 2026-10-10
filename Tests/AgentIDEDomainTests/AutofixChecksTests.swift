import AgentIDEDomain
import Testing

struct AutofixChecksTests {
    @Test
    func `required failures wait for every required result`() {
        let failed = AutofixCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", runID: "1", link: "test")
        let pending = AutofixCheck(name: "build", status: "IN_PROGRESS", conclusion: "", runID: "2", link: "build")
        #expect(AutofixChecks(required: ["test", "build"], results: [failed]).failures.isEmpty)
        #expect(AutofixChecks(required: ["test", "build"], results: [failed, pending]).failures.isEmpty)
        let passed = AutofixCheck(name: "build", status: "COMPLETED", conclusion: "SUCCESS", runID: "2", link: "build")
        #expect(AutofixChecks(required: ["test", "build"], results: [failed, passed]).failures == [failed])
    }

    @Test
    func `optional jobs neither delay nor trigger fixes`() {
        let optional = AutofixCheck(
            name: "optional",
            status: "IN_PROGRESS",
            conclusion: "FAILURE",
            runID: "2",
            link: "optional",
        )
        let failed = AutofixCheck(name: "test", status: "COMPLETED", conclusion: "FAILURE", runID: "1", link: "test")
        #expect(AutofixChecks(required: ["test"], results: [failed, optional]).failures == [failed])
        #expect(AutofixChecks(required: [], results: [failed]).failures.isEmpty)
        #expect(AutofixChecks(required: ["optional"], results: [failed, optional]).failures.isEmpty)
    }

    @Test
    func `unknown completion never counts as finished`() {
        let check = AutofixCheck(name: "test", status: "", conclusion: "FAILURE", runID: "1", link: "test")
        #expect(AutofixChecks(required: ["test"], results: [check]).failures.isEmpty)
    }
}
