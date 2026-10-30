import Darwin
import Foundation
import SanductorDomain

public extension SessionService {
    /// Watches the shared request directory; idle work is a directory event.
    func sidebarRequests() -> AsyncStream<[(id: String, request: SidebarRequest)]> {
        let directory = sidebarRequestsDirectory
        return AsyncStream { continuation in
            let task = Task {
                let wake = Self.directoryChanges(in: directory)
                var seen = Set<String>()
                while Task.isCancelled == false {
                    let requests = Self.readSidebarRequests(in: directory).filter { seen.contains($0.id) == false }
                    if requests.isEmpty == false {
                        seen.formUnion(requests.map(\.id))
                        continuation.yield(requests)
                    }
                    if let wake {
                        await wake.wait(timeout: .seconds(RefreshCadence.occludedPollSeconds))
                    } else {
                        // No directory watcher could be installed; use the existing safety cadence.
                        try? await Task.sleep(for: .seconds(RefreshCadence.occludedPollSeconds))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Publishes the acknowledgement only after the host has handled the request.
    func answerSidebarRequest(id: String, response: SidebarResponse) {
        guard UUID(uuidString: id) != nil else {
            return
        }

        let base = sidebarRequestsDirectory + "/" + id
        try? JSONEncoder().encode(response).write(to: URL(filePath: base + ".response"), options: .atomic)
        try? FileManager.default.removeItem(atPath: base + ".request")
    }

    // MARK: Internal

    internal var sidebarRequestsDirectory: String {
        paths.sanductorDirectory + "/sidebar-requests-"
            + (WorkspacePaths.isProductionBuild ? "sanductor" : "sanductor-dev")
    }

    internal static func readSidebarRequests(in directory: String) -> [(id: String, request: SidebarRequest)] {
        let manager = FileManager.default
        return ((try? manager.contentsOfDirectory(atPath: directory)) ?? []).sorted().compactMap { name in
            guard name.hasSuffix(".request") else {
                return nil
            }

            let id = String(name.dropLast(".request".count))
            let path = directory + "/" + name
            guard UUID(uuidString: id) != nil,
                  manager.fileExists(atPath: directory + "/" + id + ".response") == false
            else {
                return nil
            }

            let descriptor = unsafe open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else {
                return nil
            }

            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var attributes = stat()
            guard unsafe fstat(descriptor, &attributes) == 0,
                  attributes.st_mode & S_IFMT == S_IFREG,
                  attributes.st_size <= SidebarRequest.maximumBytes,
                  let data = try? handle.read(upToCount: SidebarRequest.maximumBytes + 1),
                  data.count <= SidebarRequest.maximumBytes,
                  let request = try? JSONDecoder().decode(SidebarRequest.self, from: data)
            else {
                return nil
            }

            return (id, request)
        }
    }
}
