/// Starts an agent on a listed pull request by number: through the
/// new session form, or at once without a prompt when `immediately`.
public typealias StartAgentAction = @MainActor (_ number: Int, _ immediately: Bool) -> Void
