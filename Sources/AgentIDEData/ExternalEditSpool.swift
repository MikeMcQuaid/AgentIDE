import AgentIDEDomain
import Foundation

/// The editor shim's spool: one request file per file a command is
/// waiting on, answered by a status file the shim reads and removes.
/// It lives in the host user's own directory, so nothing inside the
/// sandbox can queue an edit or read what is being edited.
struct ExternalEditSpool {
    // MARK: Lifecycle

    /// Creates a spool for a directory.
    init(directory: String) {
        self.directory = directory
    }

    // MARK: Internal

    /// Every request still waiting, oldest first. Requests whose
    /// command has gone (the shell it ran in closed, or the user
    /// interrupted it) are swept, so a dead command never holds a
    /// pane open.
    func pending() -> [ExternalEdit] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
        var edits = [(edit: ExternalEdit, requestedAt: Date)]()
        for name in names.sorted() where name.hasSuffix(Self.requestSuffix) {
            let id = String(name.dropLast(Self.requestSuffix.count))
            let path = directory + "/" + name
            guard let data = manager.contents(atPath: path),
                  let edit = ExternalEdit(id: id, json: data),
                  kill(edit.processIdentifier, 0) == 0 || errno == EPERM
            else {
                remove(id: id)
                continue
            }
            guard manager.fileExists(atPath: self.path(id: id, suffix: Self.doneSuffix)) == false else {
                continue
            }

            let attributes = try? manager.attributesOfItem(atPath: path)
            edits.append((edit, attributes?[.creationDate] as? Date ?? .distantPast))
        }
        return edits.sorted { $0.requestedAt < $1.requestedAt }.map(\.edit)
    }

    /// Tells the shim the app has the file on screen, so a shim that
    /// is never claimed can report that the app is not running
    /// rather than waiting for an editor that will never appear.
    func claim(_ edit: ExternalEdit) {
        write("", to: path(id: edit.id, suffix: Self.openSuffix))
    }

    /// Answers a request: a saved file lets the command carry on, a
    /// cancelled one fails it, which is how git is told to abort a
    /// rebase. The shim removes the files it read, and a request
    /// whose shim has gone is swept rather than answered.
    func finish(_ edit: ExternalEdit, saved: Bool) {
        write(saved ? "0" : "1", to: path(id: edit.id, suffix: Self.doneSuffix))
    }

    // MARK: Private

    private static let requestSuffix = ".request"
    private static let openSuffix = ".open"
    private static let doneSuffix = ".done"

    private let directory: String

    private func path(id: String, suffix: String) -> String {
        directory + "/" + id + suffix
    }

    /// Answers land in one rename, so the shim never reads half of
    /// one.
    private func write(_ contents: String, to path: String) {
        let partial = path + ".partial"
        guard (try? contents.write(toFile: partial, atomically: false, encoding: .utf8)) != nil else {
            return
        }

        try? FileManager.default.moveItem(atPath: partial, toPath: path)
    }

    private func remove(id: String) {
        for suffix in [Self.requestSuffix, Self.openSuffix, Self.doneSuffix] {
            try? FileManager.default.removeItem(atPath: path(id: id, suffix: suffix))
        }
    }
}
