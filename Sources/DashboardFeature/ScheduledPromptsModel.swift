import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation
import TerminalUI

/// Owns schedule editing and a single timer for the next due launch.
@preconcurrency
@Observable
@MainActor
public final class ScheduledPromptsModel {
    // MARK: Lifecycle

    /// Loads saved schedules without starting any work.
    public init(store: MetadataStore, service: SessionService) {
        self.store = store
        prompts = store.load().scheduledPrompts
        launch = { try await service.launchScheduledPrompt($0, due: $1) }
    }

    deinit {
        // The timer captures the app-owned model weakly.
    }

    // MARK: Public

    /// The in-memory schedules rendered by Settings.
    public private(set) var prompts: [ScheduledPrompt]
    /// The schedule whose agent is currently being launched.
    public private(set) var runningID: UUID?
    /// The last persistence failure, also preventing unrecorded launches.
    public private(set) var error: String?

    /// Edits preserve launch results, including a launch that finished
    /// while the editor was open. Only recurrence changes reset the due date.
    @discardableResult
    public func save(_ draft: ScheduledPrompt) -> Bool {
        guard draft.isValid, let next = draft.schedule.nextRun(after: now()) else {
            return false
        }

        var prompt = draft
        if let previous = prompts.first(where: { $0.id == draft.id }) {
            prompt.lastRun = previous.lastRun
            prompt.lastSession = previous.lastSession
            prompt.lastError = previous.lastError
            prompt.nextRun = previous.schedule == draft.schedule && previous.isEnabled == draft.isEnabled
                ? previous.nextRun : next
        } else {
            prompt.nextRun = next
        }
        return persist { prompts in
            prompts.removeAll { $0.id == prompt.id }
            prompts.append(prompt)
        }
    }

    /// Removes future runs while preserving existing sessions.
    public func delete(_ prompt: ScheduledPrompt) {
        _ = persist { $0.removeAll { $0.id == prompt.id } }
    }

    /// Runs each overdue schedule once. Claiming before awaiting also
    /// coalesces wake, timer and clock-change requests during a launch.
    public func runDue() async {
        guard runningID == nil else {
            return
        }

        timer?.invalidate()
        defer { armTimer() }
        let dueIDs = prompts.filter { $0.isEnabled && ($0.nextRun ?? .distantFuture) <= now() }.map(\.id)
        for id in dueIDs {
            guard let prompt = prompts.first(where: { $0.id == id }), prompt.isEnabled,
                  let due = prompt.nextRun, due <= now()
            else {
                continue
            }

            await run(prompt, due: due, advancesSchedule: true)
            if error != nil {
                return
            }
        }
    }

    /// Starts the latest saved job without moving a future occurrence or unpausing it.
    public func start(_ savedPrompt: ScheduledPrompt) async {
        guard runningID == nil, let prompt = prompts.first(where: { $0.id == savedPrompt.id }), prompt.isValid else {
            return
        }

        let due = max(now(), (prompt.lastRun ?? .distantPast).addingTimeInterval(1))
        await run(
            prompt,
            due: due,
            advancesSchedule: prompt.isEnabled && (prompt.nextRun ?? .distantFuture) <= now(),
        )
    }

    // MARK: Internal

    var now: () -> Date = Date.init
    var launch: (ScheduledPrompt, Date) async throws -> String

    // MARK: Private

    private static let saveAttempts = 2

    private let store: MetadataStore
    private var timer: Timer?

    private func run(_ prompt: ScheduledPrompt, due: Date, advancesSchedule: Bool) async {
        runningID = prompt.id
        timer?.invalidate()
        defer { runningID = nil; armTimer() }
        guard persist({ prompts in
            guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
                return
            }

            if advancesSchedule {
                prompts[index].nextRun = prompt.schedule.nextRun(after: now())
            }
            prompts[index].lastRun = max(now(), due)
            prompts[index].lastSession = nil
            prompts[index].lastError = "Launch interrupted before its result was recorded."
        }) else {
            return
        }

        var session: String?
        var failure: String?
        _ = await ErrorLog.shared.attemptingTwice("Scheduled prompt “" + prompt.name + "”") {
            do {
                session = try await self.launch(prompt, due)
                failure = nil
            } catch {
                failure = error.localizedDescription
                throw error
            }
        }
        _ = persist { prompts in
            guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else {
                return
            }

            prompts[index].lastSession = session
            prompts[index].lastError = failure
        }
        UtilityTabTarget.requestSidebarRefresh()
    }

    private func persist(_ change: (inout [ScheduledPrompt]) -> Void) -> Bool {
        var firstFailure: String?
        for _ in 0 ..< Self.saveAttempts {
            do {
                try store.updatePersisting { change(&$0.scheduledPrompts) }
                prompts = store.load().scheduledPrompts
                error = nil
                armTimer()
                return true
            } catch {
                if let firstFailure {
                    self.error = "Could not save scheduled prompts: " + firstFailure
                        + "; then again: " + error.localizedDescription
                } else {
                    firstFailure = error.localizedDescription
                    PerformanceLog.recordMessage("Saving schedules: " + error.localizedDescription, isError: true)
                }
            }
        }
        if let error {
            ErrorLog.shared.report(error)
        }
        return false
    }

    private func armTimer() {
        timer?.invalidate()
        timer = nil
        guard runningID == nil, error == nil,
              let next = prompts.filter(\.isEnabled).compactMap(\.nextRun).min()
        else {
            return
        }

        let alarm = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.runDue()
            }
        }
        timer = alarm
        RunLoop.main.add(alarm, forMode: .common)
    }
}
