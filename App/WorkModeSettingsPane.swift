import DashboardFeature
import SanductorData
import SanductorDomain
import SwiftUI

struct WorkModeSettingsPane: View {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some View {
        Form {
            Toggle("Hide work repositories outside working hours", isOn: $settings.isEnabled)
            workingHours
            Section("Organisations") {
                ForEach(organisations, id: \.self) { owner in
                    Toggle(owner, isOn: Binding(
                        get: { settings.organisations.contains(owner) },
                        set: { enabled in
                            if enabled {
                                settings.organisations.insert(owner)
                            } else {
                                settings.organisations.remove(owner)
                            }
                        },
                    ))
                }
                Text("Agents and scheduled jobs keep running while repositories are hidden.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) {
            AppSettings.workMode = settings
            dashboard.refreshWorkMode()
        }
    }

    // MARK: Private

    private static let minutesPerHour = 60

    @State private var settings: WorkMode = AppSettings.workMode

    private var organisations: [String] {
        Set(dashboard.groups.compactMap { $0.repository.owner?.lowercased() })
            .union(dashboard.cachedOrganisations().map { $0.lowercased() })
            .union(settings.organisations)
            .sorted()
    }

    private var workingHours: some View {
        Section("Working hours") {
            HStack {
                DatePicker("From", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
            }
            HStack {
                ForEach(1 ... Calendar.current.weekdaySymbols.count, id: \.self) { day in
                    Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(
                        get: { settings.weekdays.contains(day) },
                        set: { enabled in
                            if enabled {
                                settings.weekdays.insert(day)
                            } else {
                                settings.weekdays.remove(day)
                            }
                        },
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            Text("Uses this Mac's local time zone. Overnight hours end the following day; "
                + "equal times mean all day.")
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minute = start ? settings.startMinute : settings.endMinute
                return Calendar.current.date(
                    bySettingHour: minute / Self.minutesPerHour,
                    minute: minute % Self.minutesPerHour,
                    second: 0,
                    of: Date(),
                ) ?? Date()
            },
            set: { date in
                let minute = Calendar.current.component(.hour, from: date) * Self.minutesPerHour
                    + Calendar.current.component(.minute, from: date)
                if start {
                    settings.startMinute = minute
                } else {
                    settings.endMinute = minute
                }
            },
        )
    }
}
