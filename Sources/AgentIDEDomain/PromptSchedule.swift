import Foundation

/// A wall-clock recurrence in the time zone chosen at creation.
public struct PromptSchedule: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Creates a daily schedule at 09:00 in the current time zone.
    public init() {
        // All fields have defaults.
    }

    // MARK: Public

    /// The repeat choices presented by the schedule editor.
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
    }

    public static let weekdays = 1 ... 7
    public static let monthDays = 1 ... 31

    public var frequency: Frequency = .daily
    public var hour = 9
    public var minute = 0
    /// Foundation weekday numbering: Sunday is one.
    public var weekday = 2
    public var day = 1
    public var timeZoneIdentifier: String = TimeZone.current.identifier

    /// The next occurrence, skipping absent month days and taking
    /// the first instance of a repeated daylight-saving time.
    public func nextRun(after date: Date) -> Date? {
        guard Self.hours.contains(hour), Self.minutes.contains(minute),
              Self.weekdays.contains(weekday), Self.monthDays.contains(day),
              let zone = TimeZone(identifier: timeZoneIdentifier)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = DateComponents(hour: hour, minute: minute, second: 0)
        if frequency == .weekly {
            components.weekday = weekday
        } else if frequency == .monthly {
            components.day = day
        }
        var after = date
        while let next = calendar.nextDate(
            after: after, matching: components, matchingPolicy: .nextTime, repeatedTimePolicy: .first,
        ) {
            if frequency != .monthly || calendar.component(.day, from: next) == day {
                return next
            }
            after = next
        }
        return nil
    }

    // MARK: Private

    private static let hours = 0 ... 23
    private static let minutes = 0 ... 59
}
