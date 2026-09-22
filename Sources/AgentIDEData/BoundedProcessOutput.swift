import Foundation
import Synchronization

/// Pipe capture for commands whose output must never grow temporary files.
final class BoundedProcessOutput: Sendable {
    // MARK: Lifecycle

    init(limit: Int) {
        precondition(limit >= 0)
        self.limit = limit
    }

    deinit {
        // run closes both pipes after completion or launch failure.
    }

    // MARK: Internal

    func run(_ process: Process) async throws -> ProcessResult {
        process.standardOutput = output
        process.standardError = errors
        defer {
            process.terminationHandler = nil
            for pipe in [output, errors] {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            state.withLock { $0.continuation = continuation }
            process.terminationHandler = { finished in
                self.state.withLock { $0.status = finished.terminationStatus }
                self.complete()
            }
            read(output.fileHandleForReading, isError: false, process: process)
            read(errors.fileHandleForReading, isError: true, process: process)
            do {
                try process.run()
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
                stopIfNeeded(process)
            } catch {
                state.withLock { state in
                    state.finished = true
                    state.continuation = nil
                    output.fileHandleForReading.readabilityHandler = nil
                    errors.fileHandleForReading.readabilityHandler = nil
                }
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: Private

    private struct State {
        var output: Data = .init()
        var errors: Data = .init()
        var closedStreams = 0
        var status: Int32?
        var exceeded = false
        var stopping = false
        var finished = false
        var continuation: CheckedContinuation<ProcessResult, any Error>?
    }

    private static let streamCount = 2

    private let limit: Int
    private let output: Pipe = .init()
    private let errors: Pipe = .init()
    private let state: Mutex<State> = .init(State())

    private func read(_ handle: FileHandle, isError: Bool, process: Process) {
        handle.readabilityHandler = { handle in
            self.state.withLock { state in
                guard state.finished == false else {
                    return
                }

                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.closedStreams += 1
                }
                let remaining = self.limit - (isError ? state.errors.count : state.output.count)
                if isError {
                    state.errors.append(data.prefix(remaining))
                } else {
                    state.output.append(data.prefix(remaining))
                }
                state.exceeded = state.exceeded || data.count > remaining
            }
            self.stopIfNeeded(process)
            self.complete()
        }
    }

    private func stopIfNeeded(_ process: Process) {
        guard process.isRunning else {
            return
        }

        let stop = state.withLock { state in
            guard state.exceeded, state.stopping == false else {
                return false
            }

            state.stopping = true
            return true
        }
        guard stop else {
            return
        }

        process.terminate()
        // Give a launch wrapper time to relay TERM before forcing it to exit.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func complete() {
        let completed = state.withLock { state -> (CheckedContinuation<ProcessResult, any Error>, ProcessResult)? in
            guard let status = state.status,
                  state.closedStreams == Self.streamCount || state.exceeded,
                  let continuation = state.continuation
            else {
                return nil
            }

            state.finished = true
            state.continuation = nil
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            return (continuation, ProcessResult(
                status: status,
                standardOutput: String(data: state.output, encoding: .utf8) ?? "",
                standardError: String(data: state.errors, encoding: .utf8) ?? "",
                outputLimitExceeded: state.exceeded,
            ))
        }
        if let (continuation, result) = completed {
            continuation.resume(returning: result)
        }
    }
}
