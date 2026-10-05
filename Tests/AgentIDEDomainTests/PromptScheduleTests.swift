import AgentIDEDomain
import Foundation
import Testing

struct PromptScheduleTests {
    // MARK: Internal

    @Test
    func `daily and weekly dates advance strictly past the last occurrence`() throws {
        var schedule = PromptSchedule()
        schedule.timeZoneIdentifier = "Europe/London"
        #expect(try schedule.nextRun(after: date("2026-10-05T08:00:00Z")) == date("2026-10-06T08:00:00Z"))
        schedule.frequency = .weekly
        schedule.weekday = 2
        #expect(try schedule.nextRun(after: date("2026-10-05T08:00:00Z")) == date("2026-10-12T08:00:00Z"))
    }

    @Test
    func `monthly skips months without the chosen day including leap years`() throws {
        var schedule = PromptSchedule()
        schedule.timeZoneIdentifier = "UTC"
        schedule.frequency = .monthly
        schedule.day = 31
        #expect(try schedule.nextRun(after: date("2026-01-31T09:00:00Z")) == date("2026-03-31T09:00:00Z"))
        schedule.day = 29
        #expect(try schedule.nextRun(after: date("2028-01-29T09:00:00Z")) == date("2028-02-29T09:00:00Z"))
    }

    @Test
    func `daylight saving gaps run at the next valid time and repeated times run once`() throws {
        var schedule = PromptSchedule()
        schedule.timeZoneIdentifier = "Europe/London"
        schedule.hour = 1
        schedule.minute = 30
        #expect(try schedule.nextRun(after: date("2026-03-28T02:00:00Z")) == date("2026-03-29T01:00:00Z"))
        let autumn = try #require(try schedule.nextRun(after: date("2026-10-24T02:00:00Z")))
        #expect(try autumn == date("2026-10-25T00:30:00Z"))
        #expect(try schedule.nextRun(after: autumn) == date("2026-10-26T01:30:00Z"))
    }

    @Test
    func `invalid values cannot produce a run`() {
        var schedule = PromptSchedule()
        schedule.day = 32
        #expect(schedule.nextRun(after: Date()) == nil)
        schedule.day = 1
        schedule.timeZoneIdentifier = "Invalid"
        #expect(schedule.nextRun(after: Date()) == nil)
    }

    // MARK: Private

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
