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
        channel?.send(HerdrTerminal.resizeCommand(columns: terminal.cols, rows: terminal.rows))
        armFrameDeadline()
    }

    /// A stream that never renders must not hold the pane blank
    /// silently; the deadline reports enough state to name the
    /// failing layer. Frames arrive unbidden, so there is nothing to
    /// retry: a slow sudo or sandbox launch recovers by itself.
    func armFrameDeadline() {
        frameDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.frameTimeoutSeconds))
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
            if detail.isEmpty == false || sawFrames == false {
                let message = detail.isEmpty ? "the herdr client exited before attaching" : detail
                ErrorLog.shared.report("Terminal: " + message)
                self?.view?.feed(text: "\r\n[herdr client exited: " + message + "]\r\n")
            }
            callback?()
        }
    }

    // MARK: Private

    /// The deadline fired before any frame. A slow sudo or sandbox
    /// launch renders late rather than never, so this only reports;
    /// the report carries enough state to name the failing layer.
    private func reportIfBlank() {
        guard framesSeen == 0, tornDown == false else {
            return
        }

        let ended = channel
        Task {
            let running = await ended?.isRunning() ?? false
            let chain = await ended?.launchChainSnapshot() ?? "gone"
            ErrorLog.shared.report(
                "Terminal: no frames after \(Self.frameTimeoutSeconds)s"
                    + " (client running: \(running); chain: \(chain))",
            )
        }
    }
}
