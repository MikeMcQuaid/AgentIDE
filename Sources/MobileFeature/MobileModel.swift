import Foundation
import Observation
import SanductorDomain
import SanductorInterface
import SanductorRemote

// MARK: - MobileModel

/// Connection lifetime and the phone's authoritative session list.
@Observable
public final class MobileModel {
    // MARK: Lifecycle

    init(configuration: SSHConfiguration) {
        self.configuration = configuration
        isDisconnected = UserDefaults.standard.bool(forKey: "sshConnected") == false
    }

    deinit { /* Disconnect owns connection teardown. */ }

    // MARK: Public

    /// Reuses an established connection or reconnects on foregrounding.
    public func activate() {
        guard configuration.isValid, connectionTask == nil, isDisconnected == false else {
            return
        }

        UserDefaults.standard.set(try? JSONEncoder().encode(configuration), forKey: "sshConfiguration")
        isConnecting = true
        error = nil
        connectionTask = Task {
            if Task.isCancelled == false {
                await run()
            }
        }
    }

    /// Releases controllers without stopping any agents.
    public func deactivate() {
        isDisconnected = isConnected == false
        UserDefaults.standard.set(isConnected, forKey: "sshConnected")
        connectionTask?.cancel()
        connectionTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isConnected = false
        isConnecting = false
        eventChannel?.close()
        eventChannel = nil
        let previous = remote
        remote = nil
        Task {
            await previous?.disconnect()
        }
    }

    // MARK: Internal

    var configuration: SSHConfiguration
    var publicKey = ""
    var allSessions: [MobileSession] = []
    var allRepositories: [String] = []
    private(set) var defaults: [String: String] = [:]
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isDisconnected = false
    var isCreating = false
    private(set) var connectionGeneration: UUID = .init()
    var error: String?
    var pendingHostKey: String?
    let progress: LaunchProgress = .init()

    @ObservationIgnored var remote: RemoteHerdr?
    @ObservationIgnored var eventChannel: SSHCommand?
    @ObservationIgnored var eventPaneIDs: [String] = []
    @ObservationIgnored var resubscribe = false

    var sidebar: [SidebarRepository] = [] {
        didSet {
            if let selection, isHidden(selection) {
                self.selection = nil
            }
        }
    }

    var selection: MobileSession? {
        didSet {
            if let selection, isHidden(selection) {
                self.selection = nil
            }
        }
    }

    func reconnect() {
        terminalFailures = 0
        deactivate()
        isDisconnected = false
        activate()
    }

    func disconnect() {
        deactivate()
        isDisconnected = true
        UserDefaults.standard.set(false, forKey: "sshConnected")
        selection = nil
        pendingHostKey = nil
        error = nil
    }

    func didConnect() {
        if isConnected == false {
            connectionGeneration = UUID()
        }
        isConnected = true
        isConnecting = false
        UserDefaults.standard.set(true, forKey: "sshConnected")
    }

    func refresh() async {
        guard let remote, isConnected else {
            return
        }

        do {
            try await read(remote, includingPreferences: true)
        } catch {
            self.error = configuration.errorMessage(error)
        }
    }

    func terminalReady() {
        terminalFailures = 0
    }

    func terminalDisconnected() {
        guard isConnected else {
            return
        }

        terminalFailures += 1
        deactivate()
        if terminalFailures < Self.maximumAttempts {
            activate()
        } else {
            error = "The terminal could not attach after reconnecting. Try again or select another session."
        }
    }

    func read(_ client: RemoteHerdr, includingPreferences: Bool = false) async throws {
        if includingPreferences {
            async let names = client.repositories()
            async let preferences = client.defaults()
            async let ordering = client.sidebar()
            let (available, choices, orderedSidebar) = try await (names, preferences, ordering)
            try Task.checkCancellation()
            guard remote === client else {
                throw CancellationError()
            }

            if available != allRepositories {
                allRepositories = available
            }
            if choices != defaults {
                defaults = choices
            }
            if orderedSidebar != sidebar {
                sidebar = orderedSidebar
            }
        }
        let snapshot = try await client.snapshot()
        let worktrees = try await client.worktreeStatuses(in: snapshot, refresh: includingPreferences)
        let updated = MobileSession.sessions(in: snapshot, worktrees: worktrees)
        try Task.checkCancellation()
        guard remote === client else {
            throw CancellationError()
        }

        if updated != allSessions {
            allSessions = updated
        }
        if eventPaneIDs != updated.map(\.id) {
            eventPaneIDs = updated.map(\.id)
            resubscribe = true
            eventChannel?.close()
        }
        if let selected = selection,
           sessions.contains(where: { $0.id == selected.id && $0.name == selected.name }) == false
        {
            selection = nil
        }
    }

    // MARK: Private

    private static let maximumAttempts = 2

    @ObservationIgnored private var terminalFailures = 0
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false

    private func run() async {
        var failures = 0
        while failures < Self.maximumAttempts {
            let client = RemoteHerdr(configuration: configuration)
            remote = client
            error = nil
            isConnecting = true
            progress.begin(failures == 0 ? "Connecting to your Mac" : "Reconnecting to your Mac")
            do {
                try await watch(client)
            } catch {
                await client.disconnect()
                guard Task.isCancelled == false else {
                    return
                }

                refreshTask?.cancel()
                refreshTask = nil
                if isConnected {
                    failures = 0
                }
                isConnected = false
                failures += 1
                if case let SSHHostKeyError.unknown(key) = error {
                    pendingHostKey = key
                    break
                }
                if error is SSHHostKeyError || failures == Self.maximumAttempts {
                    self.error = configuration.errorMessage(error)
                    break
                }
            }
        }
        connectionTask = nil
        isConnecting = false
    }

    private func watch(_ client: RemoteHerdr) async throws {
        try await client.connect()
        try Task.checkCancellation()
        progress.report("Reading repositories and subscribing to agent changes")
        eventPaneIDs = try await MobileSession.sessions(in: client.snapshot()).map(\.id)
        try await subscribe(open: client.events) { try await receiveEvents($0, client: client) }
    }

    private func receiveEvents(_ events: SSHCommand, client: RemoteHerdr) async throws {
        var lines = RemoteLines()
        var subscribed = false
        for try await data in events.output {
            try Task.checkCancellation()
            for line in try lines.append(data) {
                let record = try JSONDecoder().decode(RemoteEvent.self, from: Data(line.utf8))
                if let failure = record.error {
                    throw RemoteError(failure.message ?? "The event stream needs to reconnect.")
                }
                if subscribed == false {
                    guard record.result?.type == "subscription_started" else {
                        throw RemoteError("The Mac did not accept the event subscription.")
                    }

                    subscribed = true
                    try await read(client, includingPreferences: isConnected == false)
                    didConnect()
                } else {
                    requestRefresh(client)
                }
            }
        }
    }

    private func requestRefresh(_ client: RemoteHerdr) {
        refreshAgain = true
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task {
            defer {
                if remote === client {
                    refreshTask = nil
                }
            }
            repeat {
                refreshAgain = false
                do {
                    try await read(client)
                } catch {
                    if Task.isCancelled == false, remote === client {
                        self.error = configuration.errorMessage(error)
                    }
                }
            } while refreshAgain && Task.isCancelled == false
        }
    }
}

// MARK: - RemoteEvent

private struct RemoteEvent: Decodable {
    let error: RemoteEventError?
    let result: RemoteEventResult?
}

// MARK: - RemoteEventError

private struct RemoteEventError: Decodable {
    let message: String?
}

// MARK: - RemoteEventResult

private struct RemoteEventResult: Decodable {
    let type: String
}
