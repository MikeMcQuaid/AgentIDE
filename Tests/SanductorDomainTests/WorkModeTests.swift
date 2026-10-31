import Foundation
import SanductorDomain
import Testing

struct WorkModeTests {
    @Test(arguments: [
        ("2026-10-30T08:59:00Z", false), ("2026-10-30T09:00:00Z", true),
        ("2026-10-30T16:59:00Z", true), ("2026-10-30T17:00:00Z", false),
        ("2026-10-31T12:00:00Z", false),
    ])
    func `working hours include the start and exclude the end`(instant: String, working: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(ISO8601DateFormatter().date(from: instant))
        var mode = WorkMode()
        mode.organisations = ["Example"]
        #expect(mode.hiddenOrganisations(at: date, calendar: calendar).isEmpty)
        mode.isEnabled = true
        #expect(mode.isWorking(at: date, calendar: calendar) == working)
        #expect(mode.hiddenOrganisations(at: date, calendar: calendar) == (working ? [] : ["example"]))
        #expect(try #require(mode.nextBoundary(after: date, calendar: calendar)) > date)
    }

    @Test
    func `a Friday overnight work extends into Saturday`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var mode = WorkMode()
        mode.startMinute = 22 * 60
        mode.endMinute = 2 * 60
        let early = try #require(ISO8601DateFormatter().date(from: "2026-10-31T01:00:00Z"))
        let late = try #require(ISO8601DateFormatter().date(from: "2026-10-31T22:00:00Z"))
        #expect(mode.isWorking(at: early, calendar: calendar))
        #expect(mode.isWorking(at: late, calendar: calendar) == false)
    }

    @Test
    func `schedule previews mask tokens without altering surrounding text`() {
        for prefix in ["sntryu_", "sntrys_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_"] {
            let prompt = "TOKEN=" + prefix + String(repeating: "a", count: 64) + " run report"
            #expect(TokenRedaction.preview(prompt) == "TOKEN=" + prefix + "*** run report")
        }
        #expect(TokenRedaction.preview("ghp_example and ordinary prose") == "ghp_example and ordinary prose")
    }
}
