import AgentIDEData
import AgentIDEDomain
import SwiftTerm

// MARK: - CommandExpectation

/// What each pending command's response means; responses arrive
/// strictly in command order.
enum CommandExpectation {
    case acknowledgement
    case history
}

// MARK: - Control mode conversation

/// The coordinator's control mode conversation: the initial
/// seed, live output, retries and the end of the stream, split
/// from the view lifecycle half for length.
extension TerminalRepresentable.Coordinator {
    /// The pane appears at its history in one round trip: size
    /// the client first so tmux settles the pane's dimensions,
    /// heal the scrollback depth on servers older than their
    /// config, then capture everything scrollback should hold.
    func requestInitialState(of view: PaneTerminalView) {
        let terminal = view.getTerminal()
        sendCommand(
            TmuxControl.resizeCommand(columns: terminal.cols, rows: terminal.rows),
            expecting: .acknowledgement,
        )
        sendCommand(TmuxControl.historyLimitCommand, expecting: .acknowledgement)
        sendCommand(TmuxControl.historyCommand, expecting: .history)
        armSeedDeadline()
    }

    /// A seed that never answers must not hold the pane blank
    /// forever; the deadline retries and eventually gives up.
    func armSeedDeadline() {
        seedDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.seedTimeoutSeconds))
            self?.seedIfStalled()
        }
    }

    /// The deadline fired before the history response. A slow
    /// sudo or sandbox launch answers late rather than never, so
    /// the capture is asked again before giving up; the final
    /// report carries enough state to name the failing layer.
    func seedIfStalled() {
        guard seeded == false, tornDown == false else {
            return
        }

        seedAttempts += 1
        if seedAttempts < Self.seedAttemptLimit {
            sendCommand(TmuxControl.historyCommand, expecting: .history)
            armSeedDeadline()
            return
        }

        let ended = channel
        let state = "responses \(responsesSeen), outputs \(outputsSeen), "
            + "notifications \(notificationsSeen), pending \(pending.count)"
        Task { [weak self] in
            let running = await ended?.isRunning() ?? false
            let chain = await ended?.launchChainSnapshot() ?? "gone"
            ErrorLog.shared.report(
                "Terminal: no history after \(Self.seedAttemptLimit) asks"
                    + " (client running: \(running), \(state); chain: \(chain));"
                    + " showing live output only",
            )
            self?.seed(lines: [])
        }
    }

    func sendCommand(_ line: String, expecting: CommandExpectation) {
        pending.append(expecting)
        channel?.send(line)
    }

    func handle(_ event: TmuxControlEvent, from sender: TmuxControlChannel) {
        // A discarded client's buffered events must not bleed
        // into the replacement's conversation.
        guard sender === channel else {
            return
        }

        switch event {
        case let .output(_, bytes):
            outputsSeen += 1
            if seeded {
                view?.feed(byteArray: bytes[...])
            } else {
                queuedOutput.append(bytes)
            }

        case let .response(lines, isError):
            responsesSeen += 1
            guard pending.isEmpty == false, pending.removeFirst() == .history else {
                return
            }

            seed(lines: isError ? [] : lines)

        case let .exited(reason):
            exitReason = reason

        case .notification:
            notificationsSeen += 1
        }
    }

    /// Feeds the captured history, replays anything queued and
    /// nudges the pane to repaint so full-screen interfaces
    /// redraw themselves over the seeded scrollback. A late or
    /// retried capture answering after the first seed is skipped:
    /// feeding old history over live output would reorder it.
    func seed(lines: [String]) {
        guard seeded == false else {
            return
        }

        let text = TmuxControl.seedText(lines: lines)
        if text.isEmpty == false {
            view?.feed(text: text)
        }
        for bytes in queuedOutput {
            view?.feed(byteArray: bytes[...])
        }
        queuedOutput = []
        seeded = true
        seedDeadline?.cancel()
        seedDeadline = nil
        nudgeRepaint()
    }

    /// A one-row shrink and restore: the resulting window change
    /// makes full-screen interfaces repaint without tmux needing
    /// a redraw command.
    func nudgeRepaint() {
        guard let terminal = view?.getTerminal() else {
            return
        }

        sendCommand(
            TmuxControl.resizeCommand(columns: terminal.cols, rows: max(terminal.rows - 1, 1)),
            expecting: .acknowledgement,
        )
        sendCommand(
            TmuxControl.resizeCommand(columns: terminal.cols, rows: terminal.rows),
            expecting: .acknowledgement,
        )
    }

    /// The stream ended: surface why when it was not a clean
    /// detach, so a failed attach never renders as a silent
    /// blank pane, then let the owner react. A discarded
    /// client's end is not news.
    func finish(for ended: TmuxControlChannel) {
        guard tornDown == false, ended === channel else {
            return
        }

        let callback = onProcessTerminated
        onProcessTerminated = nil
        let reason = exitReason
        let wasSeeded = seeded
        channel = nil
        Task { [weak self] in
            let diagnostics = await ended.collectedErrorText()
            let detail = [reason, diagnostics.isEmpty ? nil : diagnostics]
                .compactMap(\.self)
                .joined(separator: "; ")
            if detail.isEmpty == false || wasSeeded == false {
                let message = detail.isEmpty ? "the tmux client exited before attaching" : detail
                ErrorLog.shared.report("Terminal: " + message)
                self?.view?.feed(text: "\r\n[tmux client exited: " + message + "]\r\n")
            }
            callback?()
        }
    }
}
