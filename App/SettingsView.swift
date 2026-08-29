import AgentIDEData
import AgentIDEDomain
import DashboardFeature
import SwiftUI
import TerminalUI

// MARK: - SettingsView

/// The Settings window (Cmd-,): the preferences that were scattered
/// across menus, hidden defaults keys and constants, in one place.
struct SettingsView: View {
    // MARK: Internal

    let dependencies: AppDependencies

    var body: some View {
        TabView {
            GeneralSettingsPane(dashboard: dependencies.dashboard)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsSettingsPane()
                .tabItem { Label("Notifications", systemImage: "bell") }
            EditorSettingsPane()
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
            AdvancedSettingsPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: Self.width)
    }

    // MARK: Private

    private static let width: CGFloat = 560
}

// MARK: - GeneralSettingsPane

/// Defaults for new sessions, the signing policy and the way to the
/// session manager.
private struct GeneralSettingsPane: View {
    // MARK: Internal

    let dashboard: DashboardModel

    var body: some View {
        Form {
            Section("New sessions") {
                AgentOptionPickers(
                    agent: agentBinding,
                    model: $agentModel,
                    effort: $agentEffort,
                    choices: dashboard.launchChoices,
                )
                Text("What the new session form starts on; each form remembers later changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pushing") {
                Toggle("Require signed commits before pushing", isOn: $requireSignedCommits)
                Text("Off, pushes skip the tip's signature check, for remotes without a "
                    + "signing hook; rebases still sign.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sessions") {
                Button("Manage Sessions…") {
                    NSApp.activate()
                    dashboard.showsSessionManager = true
                }
                Text("Every agent, shell and browser pane with what it costs, in the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    /// The same keys the new session form persists through, so the
    /// default set here is simply what the next form opens on.
    @AppStorage("agentKind")
    private var agentKindName = AgentKind.claudeCode.rawValue
    @AppStorage("agentModel")
    private var agentModel = ""
    @AppStorage("agentEffort")
    private var agentEffort = ""
    @AppStorage(AppSettings.requireSignedCommitsKey)
    private var requireSignedCommits = true

    private var agentBinding: Binding<AgentKind> {
        Binding(
            get: { AgentKind(rawValue: agentKindName) ?? .claudeCode },
            set: { agentKindName = $0.rawValue },
        )
    }
}

// MARK: - AdvancedSettingsPane

/// Cadences and machinery: how often the system is re-read, sleep
/// inhibition and the performance log.
private struct AdvancedSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            cadenceSection
            machineSection
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    private static let pollRange = 2 ... 60
    private static let stackRange: ClosedRange<Double> = 15 ... 600
    private static let stackStep: Double = 15

    /// Literal defaults, matching `AppSettings`' own: the formatter
    /// rewrites `Type.member` initialisers into broken type
    /// annotations, so the shared constants cannot be named here.
    @AppStorage(AppSettings.pollIntervalKey)
    private var pollSeconds = 5
    @AppStorage(AppSettings.stackIntervalKey)
    private var stackSeconds = 60.0
    @AppStorage(AppSettings.inhibitsSleepKey)
    private var inhibitsSleep = true

    /// Redraws the toggle when flipped; the truth lives in the
    /// marker file `PerformanceLog` reads.
    @State private var logGeneration = 0

    private var performanceLogBinding: Binding<Bool> {
        Binding(
            get: {
                _ = logGeneration
                return PerformanceLog.isEnabled
            },
            set: { enabled in
                PerformanceLog.setEnabled(enabled)
                logGeneration += 1
            },
        )
    }

    private var cadenceSection: some View {
        Section("Cadence") {
            Stepper(
                "Refresh every " + String(pollSeconds) + " s",
                value: $pollSeconds,
                in: Self.pollRange,
            )
            Text("How often herdr, git and transcripts are re-read while the window is "
                + "visible; hidden windows drop to a minute regardless.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(
                "Re-derive stacks every " + String(Int(stackSeconds)) + " s",
                value: $stackSeconds,
                in: Self.stackRange,
                step: Self.stackStep,
            )
            Text("How long a derived branch stack is trusted; lone branches wait five "
                + "times as long.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var machineSection: some View {
        Section("Machine") {
            Toggle("Keep the Mac awake while agents or shells run", isOn: $inhibitsSleep)
            Text("Blocks idle sleep only; closing the lid still sleeps.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Performance log", isOn: performanceLogBinding)
            Text("Records every process, network call and cache decision to the shared "
                + "log, the switch script/performance-log flips.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
