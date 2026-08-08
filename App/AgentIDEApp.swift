import SwiftUI

@main
struct AgentIDEApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }

    // MARK: Private

    private let dependencies: AppDependencies = .init()
}
