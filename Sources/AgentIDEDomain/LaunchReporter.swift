/// Where a launch narrates its steps: creation and resumes report
/// each step and what it waits on as it happens, and the pane
/// covering the split shows them. Main-actor bound because that is
/// where the narration is displayed; services await each report.
public typealias LaunchReporter = @MainActor @Sendable (String) -> Void

/// The reporter for launches nobody is watching.
public let silentLaunchReporter: LaunchReporter = { _ in
    // Nobody is watching.
}
