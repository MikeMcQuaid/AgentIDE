/// Something GitHub numbers within a repository, an issue or a pull
/// request, as its pickers show and search it.
public protocol NumberedItem {
    /// The number GitHub gave it.
    var number: Int { get }

    /// Its title.
    var title: String { get }
}
