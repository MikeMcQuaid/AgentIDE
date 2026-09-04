@testable import AgentIDEDomain
import Testing

/// Where a drag's end lands: the boundary nearest the pointer, so
/// the character under it is inside the selection.
struct TerminalSelectionTests {
    @Test
    func `a pointer past the middle of a cell takes that character`() {
        // Ten-point cells: two thirds across cell six is nearer the
        // boundary after it, so the end names seven and the copy,
        // which stops before its end column, carries cell six.
        #expect(TerminalSelection.endColumn(across: 66, cellWidth: 10, columns: 80) == 7)
        // Before the middle, the boundary before it is nearer, which
        // is what the terminal already did.
        #expect(TerminalSelection.endColumn(across: 64, cellWidth: 10, columns: 80) == 6)
        // Exactly on a boundary names it.
        #expect(TerminalSelection.endColumn(across: 60, cellWidth: 10, columns: 80) == 6)
    }

    @Test
    func `the end never leaves the row`() {
        // The row's last boundary is its column count: an end there
        // selects to the end of the line and no further.
        #expect(TerminalSelection.endColumn(across: 10_000, cellWidth: 10, columns: 80) == 80)
        // A drag off the left edge reports negative distances.
        #expect(TerminalSelection.endColumn(across: -40, cellWidth: 10, columns: 80) == 0)
    }

    @Test
    func `a grid with nothing to measure against answers nothing`() {
        #expect(TerminalSelection.endColumn(across: 66, cellWidth: 0, columns: 80) == nil)
        #expect(TerminalSelection.endColumn(across: 66, cellWidth: 10, columns: 0) == nil)
    }
}
