import Foundation
import SanductorDomain

public extension AppSettings {
    /// Organisation visibility and local working hours.
    static var workMode: WorkMode {
        get {
            UserDefaults.standard
                .data(forKey: "workMode")
                .flatMap { try? JSONDecoder().decode(WorkMode.self, from: $0) } ?? WorkMode()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "workMode") }
    }
}
