/// Where a drag's end sits along a row of fixed-width cells.
public enum TerminalSelection {
    /// The column a drag's end should name: the boundary nearest the
    /// pointer, counted in cells from the left edge.
    ///
    /// A terminal names the cell the pointer is inside and takes the
    /// end as exclusive, so the character under the pointer is left
    /// out of both the highlight and the copy, and a drag across a
    /// word drops its last letter. Past the middle of a cell the
    /// boundary after it is the nearer one, which is the character
    /// every other text surface on the Mac selects. Nil when there is
    /// no grid to measure against.
    public static func endColumn(across: Double, cellWidth: Double, columns: Int) -> Int? {
        guard cellWidth > 0, columns > 0 else {
            return nil
        }

        let boundary = Int((across / cellWidth).rounded())
        return min(max(boundary, 0), columns)
    }
}
