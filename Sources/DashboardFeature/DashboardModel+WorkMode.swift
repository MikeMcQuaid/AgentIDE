import Foundation
import SanductorData
import SanductorDomain

public extension DashboardModel {
    /// Repositories visible during the current working hours.
    var visibleGroups: [RepositoryGroup] {
        groups.filter { hiddenOrganisations.contains($0.repository.owner?.lowercased() ?? "") == false }
    }

    /// Rechecks visibility and schedules the next local-time boundary.
    func refreshWorkMode(onlyIfSettingsChanged: Bool = false) {
        let settings = AppSettings.workMode
        guard onlyIfSettingsChanged == false || workModeSettings != settings else {
            return
        }

        workModeSettings = settings
        let hidden = settings.hiddenOrganisations(at: Date())
        if hiddenOrganisations != hidden {
            hiddenOrganisations = hidden
            cacheSidebar(groups)
        }
        if let selection, hidden.contains(groups.group(holding: selection)?.repository.owner?.lowercased() ?? "") {
            self.selection = nil
        }
        workModeTimer?.invalidate()
        workModeTimer = nil
        guard let next = settings.nextBoundary(after: Date()) else {
            return
        }

        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWorkMode()
            }
        }
        workModeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
