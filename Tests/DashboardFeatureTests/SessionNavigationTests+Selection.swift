@testable import DashboardFeature
import Foundation
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `command selection toggles rows without navigating and survives regrouping`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let second = Fixture.item("second", repository: fixture.repository)
        fixture.model.groups[0].items.append(second)
        fixture.model.select(first)
        fixture.model.selectSidebar(second, extending: true)
        #expect(fixture.model.selectedItems == [first, second])
        #expect(fixture.model.selection?.id == first.id)
        fixture.model.selectSidebar(first, extending: true)
        #expect(fixture.model.selectedItems == [second])
        #expect(fixture.model.selection?.id == first.id)
        #expect(fixture.model.actionItems(for: first) == [first])
        fixture.model.selectSidebar(first, extending: true)
        fixture.model.groups[0].items = [second, first]
        #expect(fixture.model.selectedItems == [second, first])
        #expect(fixture.model.actionItems(for: second) == [second, first])
        fixture.model.selectSidebar(first, extending: false)
        #expect(fixture.model.selectedItems == [first])
    }

    @Test
    func `removed rows leave the selection and busy batches cannot change it`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let second = Fixture.item("second", repository: fixture.repository)
        fixture.model.groups[0].items.append(second)
        fixture.model.select(first)
        fixture.model.selectSidebar(second, extending: true)
        fixture.model.batchAction = .fetch
        fixture.model.selectSidebar(first, extending: false)
        fixture.model.selectSidebar(second, extending: true)
        #expect(fixture.model.selectedItems == [first, second])
        fixture.model.batchAction = nil
        fixture.model.groups[0].items = [first]
        fixture.model.groups[0].items.append(second)
        #expect(fixture.model.selectedItems == [first])
    }

    @Test
    func `repository actions deduplicate while reset and cleanup keep their scopes`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let main = try #require(fixture.model.groups.first?.items.first)
        let second = Fixture.item("second", repository: fixture.repository)
        let third = Fixture.item("third", repository: fixture.repository)
        let other = Fixture.item("main", repository: Repository(name: "other", path: "/other"))
        let items = [main, second, third, other]
        fixture.model.groups[0].items = items
        #expect(fixture.model.batchItems(for: .refresh, in: items) == [main, other])
        #expect(fixture.model.batchItems(for: .fetch, in: items) == [main, other])
        #expect(fixture.model.batchItems(for: .fetchAndReset, in: items) == [main])
        #expect(fixture.model.batchItems(for: .cleanUp, in: items) == [second, third, other])
    }

    @Test(arguments: WorkBlock.Scope.allCases)
    func `a shared blocker persists and late removal keeps newer edits`(scope: WorkBlock.Scope) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let second = Fixture.item("second", repository: fixture.repository)
        fixture.model.groups[0].items.append(second)
        fixture.model.select(first)
        fixture.model.selectSidebar(second, extending: true)
        let selection = WorktreeBlockSelection(items: [first, second], model: fixture.model)
        let block = WorkBlock(target: SidebarTarget(first.worktree), scope: scope, dependency: .note("Release"))
        #expect(fixture.model.editBlocks(block, targets: selection.targets, replacing: []) == nil)
        let captured = WorktreeBlockSelection(items: [first, second], model: fixture.model)
        #expect(captured.commonBlock?.dependency == block.dependency)
        #expect(fixture.model.statusGroups.first?.items == [first, second])
        #expect(fixture.model.statusGroups.first?.status == .blocked)
        #expect(fixture.model.selectedItems == [first, second])
        #expect(fixture.model.store.load().workBlocks.count == 2)
        let newer = WorkBlock(target: SidebarTarget(second.worktree), scope: scope, dependency: .note("New reason"))
        #expect(fixture.model.editBlocks(newer, targets: [newer.target], replacing: []) == nil)
        #expect(fixture.model.editBlocks(nil, targets: captured.targets, replacing: captured.blocks) == nil)
        #expect(fixture.model.block(for: first) == nil)
        #expect(fixture.model.block(for: second)?.dependency == newer.dependency)
    }

    @Test(arguments: [true, false])
    func `one invalid member cannot partially block a selection`(stale: Bool) throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = try #require(fixture.model.groups.first?.items.first)
        let second = Fixture.item("second", repository: fixture.repository)
        fixture.model.groups[0].items.append(second)
        let selection = WorktreeBlockSelection(items: [first, second], model: fixture.model)
        if stale {
            fixture.model.groups[0].items[1] = second.renamed(branch: "changed")
        }
        let block = WorkBlock(
            target: SidebarTarget(first.worktree),
            scope: .worktree,
            dependency: stale ? .note("Wait") : .worktree(SidebarTarget(second.worktree)),
        )
        #expect(fixture.model.editBlocks(block, targets: selection.targets, replacing: []) != nil)
        #expect(fixture.model.workBlocks.isEmpty)
        #expect(fixture.model.store.load().workBlocks.isEmpty)
    }
}

extension SessionNavigationTests.Fixture {
    static func item(_ branch: String, repository: Repository) -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: repository.name,
                repositoryPath: repository.path,
                branch: branch,
                path: repository.path + "/" + branch,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
    }
}
