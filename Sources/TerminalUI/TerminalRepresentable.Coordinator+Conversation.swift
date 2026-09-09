import AgentIDEData
import AgentIDEDomain
import SwiftTerm

// MARK: - Herdr stream conversation

/// The coordinator's herdr stream conversation: the opening frame,
/// live frames and the end of the stream, split from the view
/// lifecycle half for length.
extension TerminalRepresentable.Coordinator {
    /// Sizes the controller to the view as soon as the stream
    /// starts, which drives the pane's size; the stream opens with a
    /// full repaint that also restores the pane's terminal modes, so
    /// there is nothing to seed and pastes bracket themselves.
    func requestInitialState(of view: PaneTerminalView) {
        let terminal = view.getTerminal()
        sendResize(columns: terminal.cols, rows: terminal.rows)
        armFrameDeadline()
    }

    /// Tells herdr the pane's size, once per size: see `sentSize`.
    func sendResize(columns: Int, rows: Int) {
        guard sentSize?.columns != columns || sentSize?.rows != rows else {
            return
        }

        sentSize = (columns, rows)
        channel?.send(HerdrTerminal.resizeCommand(columns: columns, rows: rows))
    }

    /// A stream that never renders must not hold the pane blank
    /// silently; the deadline reports enough state to name the
    /// failing layer. Frames arrive unbidden, so there is nothing to
    /// retry: a slow sudo or sandbox launch recovers by itself.
    func armFrameDeadline() {
        frameDeadline = Task { [weak self] in
            // A deadline cut short was cancelled for a fresh client,
            // whose own deadline is the one that counts.
            guard await (try? Task.sleep(for: .seconds(Self.frameTimeoutSeconds))) != nil else {
                return
            }

            self?.reportIfBlank()
        }
    }

    func handle(_ event: HerdrTerminalEvent, from sender: HerdrTerminalChannel) {
        // A discarded client's buffered events must not bleed
        // into the replacement's conversation.
        guard sender === channel else {
            return
        }

        switch event {
        case let .frame(bytes):
            framesSeen += 1
            // The first frame is recovery succeeding: whatever the
            // attempt before it did wrong is not news.
            heldFailure = nil
            view?.feed(byteArray: bytes[...])
            blockSelector?.follow()

        case let .closed(reason):
            exitReason = reason
        }
    }

    /// The stream ended: surface why when it was not a clean
    /// release, so a failed attach never renders as a silent
    /// blank pane, then let the owner react. A discarded
    /// client's end is not news.
    func finish(for ended: HerdrTerminalChannel) {
        guard tornDown == false, ended === channel else {
            return
        }

        let callback = onProcessTerminated
        onProcessTerminated = nil
        let reason = exitReason
        let sawFrames = framesSeen > 0
        channel = nil
        Task { [weak self] in
            let diagnostics = await ended.collectedErrorText()
            let detail = [reason, diagnostics.isEmpty ? nil : diagnostics]
                .compactMap(\.self)
                .joined(separator: "; ")
            // A terminal that ended because its session was closed or
            // its worktree went is not news: the pane is about to
            // leave the screen. Only an attach that never drew, or a
            // client that said something went wrong, is an error.
            let expected = Self.isExpectedExit(reason)
            if (detail.isEmpty == false && expected == false) || sawFrames == false {
                let message = detail.isEmpty ? "the herdr client exited before attaching" : detail
                self?.failed(message)
            } else if let reason, expected {
                ErrorLog.shared.note("Terminal: " + reason)
            }
            callback?()
        }
    }

    /// A client that ended without drawing. Held while recovery has
    /// yet to be tried: a stale pane target is replaced by the next
    /// listing's transport, and a running client that draws nothing
    /// is reattached, and either drawing a frame makes the failure
    /// not news. Once recovery has been tried, reported at once with
    /// what was held.
    func failed(_ message: String) {
        guard reattachments >= Self.automaticReattachments || heldFailure != nil else {
            heldFailure = message
            PerformanceLog.recordMessage("Terminal: " + message + " (held while recovery is tried)", isError: true)
            return
        }

        report(message)
    }

    // MARK: Private

    /// Reports a failure and whatever was held before it, and says
    /// so in the pane.
    private func report(_ message: String) {
        let whole = heldFailure.map { $0 + "; then " + message } ?? message
        heldFailure = nil
        ErrorLog.shared.report("Terminal: " + whole)
        view?.feed(text: "\r\n[herdr client exited: " + whole + "]\r\n")
    }

    /// Whether the client's reason for ending is the terminal simply
    /// being gone: herdr words a closed target as the session having
    /// exited, which is what closing it asked for.
    private static func isExpectedExit(_ reason: String?) -> Bool {
        guard let reason else {
            return true
        }

        return reason.contains(" exited") || reason.contains("not found")
    }

    /// The deadline fired before any frame. A client that is running
    /// yet drew nothing is discarded and attached afresh, once and
    /// silently: every pane once went blank at the same time with
    /// its sessions running on, and only a relaunch brought them
    /// back. Only a pane still blank after that is reported, with
    /// enough state to name the failing layer.
    private func reportIfBlank() {
        guard framesSeen == 0, tornDown == false else {
            return
        }

        let ended = channel
        Task { [weak self] in
            let running = await ended?.isRunning() ?? false
            let chain = await ended?.launchChainSnapshot() ?? "gone"
            let state = " (client running: \(running); chain: \(chain))"
            guard let self else {
                return
            }

            if running, reattachments < Self.automaticReattachments, let view {
                PerformanceLog.recordMessage(
                    "Terminal: no frames after \(Self.frameTimeoutSeconds)s" + state + "; reattaching",
                    isError: false,
                )
                reattach(in: view)
                return
            }

            report("no frames after \(Self.frameTimeoutSeconds)s"
                + (reattachments > 0 ? " and none after reattaching" : "") + state)
        }
    }
}
