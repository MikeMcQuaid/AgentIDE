import SanductorData
import SanductorDomain

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
        let terminal = view.terminalDimensions
        sendResize(columns: terminal.cols, rows: terminal.rows)
    }

    /// Tells herdr the pane's size, once per size: see `sentSize`.
    func sendResize(columns: Int, rows: Int) {
        guard sentSize?.columns != columns || sentSize?.rows != rows else {
            return
        }

        sentSize = (columns, rows)
        channel?.send(HerdrTerminal.resizeCommand(columns: columns, rows: rows))
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
            if reason == HerdrTerminal.takeoverReason {
                heldFailure = nil
                onHandoff?(true)
            }
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

        let reason = exitReason
        channel = nil
        guard reason != HerdrTerminal.takeoverReason else {
            return
        }

        let callback = onProcessTerminated
        onProcessTerminated = nil
        let sawFrames = framesSeen > 0
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

    /// An exited client's diagnostic. Held from Messages while recovery
    /// has yet to be tried: a stale pane target is replaced by the next
    /// listing's transport. A frame from the replacement clears the
    /// failure; another failure or a failed manual retry reports it.
    func failed(_ message: String) {
        guard reattachments > 0 || heldFailure != nil else {
            heldFailure = message
            PerformanceLog.recordMessage("Terminal: " + message + " (held while recovery is tried)", isError: true)
            view?.feed(text: "\r\n[herdr client exited: " + message + "]\r\n")
            return
        }

        let whole = heldFailure.map { $0 + "; then " + message } ?? message
        heldFailure = nil
        ErrorLog.shared.report("Terminal: " + whole)
        view?.feed(text: "\r\n[herdr client exited: " + whole + "]\r\n")
    }

    // MARK: Private

    /// Whether the client's reason for ending is the terminal simply
    /// being gone: herdr words a closed target as the session having
    /// exited, which is what closing it asked for.
    private static func isExpectedExit(_ reason: String?) -> Bool {
        guard let reason else {
            return true
        }

        return reason.contains(" exited") || reason.contains("not found")
    }
}
