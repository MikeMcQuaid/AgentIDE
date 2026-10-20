#if os(iOS)
    import MobileFeature
    import SwiftUI

    @main
    struct AgentIDEApp: App {
        // MARK: Internal

        var body: some Scene {
            WindowGroup {
                MobileRootView(model: model)
                    .onChange(of: scenePhase, initial: true) { _, phase in
                        if phase == .active {
                            model.activate()
                        } else if phase == .background {
                            model.suspend()
                        }
                    }
            }
        }

        // MARK: Private

        @Environment(\.scenePhase)
        private var scenePhase
        @State private var model: MobileModel = .init()
    }
#endif
