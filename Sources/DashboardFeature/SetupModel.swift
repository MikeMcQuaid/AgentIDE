import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation

/// Revalidates completed setup in the background and gates the app on failures.
@Observable
public final class SetupModel {
    // MARK: Lifecycle

    /// Supplies the asynchronous checks and persistent first-setup marker.
    @preconcurrency
    public init(check: @escaping @Sendable (Bool) async -> SetupResult, defaults: UserDefaults = .standard) {
        self.check = check
        self.defaults = defaults
        isReady = defaults.bool(forKey: Self.completedKey)
    }

    deinit {
        // No resources to release.
    }

    // MARK: Public

    /// Whether the dashboard and its background work may start.
    public private(set) var isReady = false
    /// Prevents overlapping checks while keeping Exit available.
    public private(set) var isChecking = false
    /// The unmet prerequisites shown in the blocking window.
    public private(set) var issues: [SetupIssue] = []
    /// Installed agents whose local sign-in check passed.
    public private(set) var agents: [AgentKind] = []
    /// Explains the automatic fallback without blocking setup.
    public private(set) var signingDisabled = false

    /// The wizard shows one unmet prerequisite at a time.
    public var currentIssue: SetupIssue? {
        issues.first
    }

    /// Runs once per launch even when completed setup opens the workspace immediately.
    public func checkOnLaunch() async {
        guard hasChecked == false else {
            return
        }

        await recheck()
    }

    /// Retries setup, contacting GitHub only until the first complete success.
    public func recheck() async {
        guard isChecking == false else {
            return
        }

        isChecking = true
        hasChecked = true
        defer { isChecking = false }
        let result = await check(defaults.bool(forKey: Self.completedKey) == false)
        issues = result.issues
        agents = result.agents
        if result.signingConfigured == false,
           defaults.bool(forKey: Self.completedKey) == false,
           defaults.object(forKey: AppSettings.requireSignedCommitsKey) == nil
        {
            defaults.set(false, forKey: AppSettings.requireSignedCommitsKey)
            signingDisabled = true
        }
        guard issues.isEmpty else {
            isReady = false
            return
        }

        if agents.contains(where: { $0.rawValue == defaults.string(forKey: "agentKind") }) == false {
            defaults.set(agents.first?.rawValue, forKey: "agentKind")
        }
        defaults.set(true, forKey: Self.completedKey)
        isReady = true
    }

    // MARK: Internal

    static let completedKey = "initialSetupCompleted"

    // MARK: Private

    private let check: @Sendable (Bool) async -> SetupResult
    private let defaults: UserDefaults
    @ObservationIgnored private var hasChecked = false
}
