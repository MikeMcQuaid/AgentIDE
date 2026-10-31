/// The three panes introduced after a new user's setup checks pass.
public enum SetupTourStep: Int {
    /// Repository selection and separate worktrees.
    case repositories = 0
    /// Sandboxed agents and their trust boundary.
    case agent = 1
    /// Review tools and the host user's shell.
    case tools = 2
}
