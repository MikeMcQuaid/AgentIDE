import AgentIDEData
import AgentIDEDomain
import AppKit
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
            signingSection
            linksSection
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

    /// The apps registered for web links, by their shown names.
    private static let browsers: [(name: String, path: String)] = {
        guard let web = URL(string: "https://example.com") else {
            return []
        }

        return NSWorkspace.shared
            .urlsForApplications(toOpen: web)
            .map { (name: FileManager.default.displayName(atPath: $0.path), path: $0.path) }
            .sorted { $0.name < $1.name }
    }()

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
    @AppStorage(AppSettings.externalBrowserKey)
    private var externalBrowser = ""

    private var agentBinding: Binding<AgentKind> {
        Binding(
            get: { AgentKind(rawValue: agentKindName) ?? .claudeCode },
            set: { agentKindName = $0.rawValue },
        )
    }

    private var signingSection: some View {
        Section("Signing") {
            Toggle("Require signed commits", isOn: $requireSignedCommits)
            Text("Off, nothing signs or checks signatures: rebases stop passing "
                + "--gpg-sign and pushes skip the tip check.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var linksSection: some View {
        Section("Links") {
            Picker("Cmd-click opens", selection: $externalBrowser) {
                Text("Default browser").tag("")
                ForEach(Self.browsers, id: \.path) { browser in
                    Text(browser.name).tag(browser.path)
                }
            }
            Text("Where a Cmd-clicked web link goes; a plain click stays in the "
                + "embedded browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AdvancedSettingsPane

/// Cadences and machinery: how often the system is re-read, sleep
/// inhibition and the performance log.
private struct AdvancedSettingsPane: View {
    // MARK: Internal

    var body: some View {
        Form {
            locationsSection
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

    private var locationsSection: some View {
        let shared = WorkspacePaths.current().sharedWorkspace
        return Section("Locations") {
            LocationRow(
                title: "Repositories",
                key: AppSettings.repositoriesDirectoryKey,
                fallback: shared + "/repositories",
            )
            LocationRow(
                title: "Worktrees",
                key: AppSettings.worktreesDirectoryKey,
                fallback: shared + "/worktrees",
            )
            Text("Where checkouts and worktrees live; the defaults are the shared "
                + "workspace's own directories. Takes effect on the next refresh; the "
                + "bundled agentide command keeps the defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cadenceSection: some View {
        Section("Cadence") {
            LabeledContent("Refresh every") {
                Stepper(String(pollSeconds) + " s", value: $pollSeconds, in: Self.pollRange)
            }
            Text("How often herdr, git and transcripts are re-read while the window is "
                + "visible; hidden windows drop to a minute regardless.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Re-derive stacks every") {
                Stepper(
                    String(Int(stackSeconds)) + " s",
                    value: $stackSeconds,
                    in: Self.stackRange,
                    step: Self.stackStep,
                )
            }
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

// MARK: - LocationRow

/// One Settings-chosen directory: the current pick or its default,
/// a chooser and the way back.
private struct LocationRow: View {
    // MARK: Lifecycle

    init(title: String, key: String, fallback: String) {
        self.title = title
        self.fallback = fallback
        _stored = AppStorage(wrappedValue: "", key)
    }

    // MARK: Internal

    let title: String
    let fallback: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(stored.isEmpty ? fallback : stored)
                    .foregroundStyle(stored.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") { choose() }
                    .hoverHelp("Pick another directory")
                if stored.isEmpty == false {
                    Button("Default") { stored = "" }
                        .hoverHelp("Back to " + fallback)
                }
            }
        }
    }

    // MARK: Private

    @AppStorage private var stored: String

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: stored.isEmpty ? fallback : stored)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        stored = url.path
    }
}
