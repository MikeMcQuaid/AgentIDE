import Foundation

/// A local-time visibility schedule; it never controls agent or job execution.
public struct WorkMode: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init() {
        // Weekdays, 09:00–17:00 by default.
    }

    // MARK: Public

    public var isEnabled = false
    public var organisations: Set<String> = []
    // swiftlint:disable:next no_magic_numbers - Calendar weekday numbering.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    // swiftlint:disable:next no_magic_numbers - Default working hours.
    public var startMinute = 9 * Self.minutesPerHour
    // swiftlint:disable:next no_magic_numbers - Default working hours.
    public var endMinute = 17 * Self.minutesPerHour

    public func isWorking(at date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * Self.minutesPerHour
            + calendar.component(.minute, from: date)
        let day = calendar.component(.weekday, from: date)
        if startMinute < endMinute {
            return weekdays.contains(day) && (startMinute ..< endMinute).contains(minute)
        }
        if startMinute == endMinute {
            return weekdays.contains(day)
        }
        let previousDay = day == 1 ? calendar.weekdaySymbols.count : day - 1
        return (weekdays.contains(day) && minute >= startMinute)
            || (weekdays.contains(previousDay) && minute < endMinute)
    }

    public func hiddenOrganisations(at date: Date, calendar: Calendar = .current) -> Set<String> {
        if isEnabled, isWorking(at: date, calendar: calendar) == false {
            Set(organisations.map { $0.lowercased() })
        } else {
            []
        }
    }

    public func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else {
            return nil
        }

        return [0, startMinute, endMinute]
            .compactMap { minute in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(hour: minute / Self.minutesPerHour, minute: minute % Self.minutesPerHour),
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                )
            }
            .min()
    }

    // MARK: Private

    private static let minutesPerHour = 60
}
