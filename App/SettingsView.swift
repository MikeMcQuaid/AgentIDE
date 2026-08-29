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
                    .hoverHelp("Off, Push stops checking for a GPG signature on the tip: only for "
                        + "repositories whose remote runs no signature hook. Rebase still signs.")
            }
            Section("Sessions") {
                Button("Manage Sessions…") {
                    NSApp.activate()
                    dashboard.showsSessionManager = true
                }
                .hoverHelp("Everything running and what it costs, in the main window")
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
            Section("Cadence") {
                Stepper(
                    "Refresh every " + String(pollSeconds) + " s",
                    value: $pollSeconds,
                    in: Self.pollRange,
                )
                .hoverHelp("How often herdr, git and the transcripts are re-read while the "
                    + "window is visible; hidden windows drop to a minute regardless")
                Stepper(
                    "Re-derive stacks every " + String(Int(stackSeconds)) + " s",
                    value: $stackSeconds,
                    in: Self.stackRange,
                    step: Self.stackStep,
                )
                .hoverHelp("How long a derived branch stack is trusted; lone branches wait "
                    + "five times as long")
            }
            Section("Machine") {
                Toggle("Keep the Mac awake while agents or shells run", isOn: $inhibitsSleep)
                    .hoverHelp("Blocks idle sleep only; closing the lid still sleeps. Applies "
                        + "as work starts and stops.")
                Toggle("Performance log", isOn: performanceLogBinding)
                    .hoverHelp("Writes every process, network call and cache decision to "
                        + "`tmp/agentide/performance.log`, the switch `script/performance-log` "
                        + "flips; the environment variable, when set, always wins")
            }
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
}
