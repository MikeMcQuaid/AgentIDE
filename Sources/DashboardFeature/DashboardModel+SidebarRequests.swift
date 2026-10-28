import SanductorDomain

extension DashboardModel {
    func listenForSidebarRequests() async {
        for await requests in service.sidebarRequests() {
            for request in requests {
                if case .refreshStatus = request.request {
                    startStatusDetailsRefresh()
                }
                let response = await service.handleSidebarRequest(request.request, groups: groups)
                updateWorkBlocks()
                service.answerSidebarRequest(id: request.id, response: response)
            }
        }
    }
}
