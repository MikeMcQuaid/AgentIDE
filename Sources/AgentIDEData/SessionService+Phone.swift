import AgentIDEDomain
import Foundation

public extension SessionService {
    /// Publishes the sidebar projection without exposing the host's metadata file.
    func publishSidebar(_ repositories: [SidebarRepository]) -> Bool {
        do {
            try FileManager.default.createDirectory(atPath: paths.agentideDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(repositories).write(
                to: URL(filePath: paths.agentideDirectory + "/sidebar-"
                    + (WorkspacePaths.isProductionBuild ? "agentide" : "agentide-dev") + ".json"),
                options: .atomic,
            )
            return true
        } catch {
            return false
        }
    }
}
