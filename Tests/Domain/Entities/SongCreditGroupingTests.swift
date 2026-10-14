import Testing
@testable import GHallelujah

struct SongCreditGroupingTests {
    @Test func creditsGroupUnderTheirCategory() {
        let groups = [
            SongCredit.fixture(name: "A", category: "Production"),
            SongCredit.fixture(name: "B", category: "Writing"),
            SongCredit.fixture(name: "C", category: "Production")
        ].groupedByCategory()

        #expect(groups.map(\.category) == ["Production", "Writing"])
        #expect(groups[0].credits.map(\.name) == ["A", "C"])
        #expect(groups[1].credits.map(\.name) == ["B"])
    }

    @Test func blankOrMissingCategoryFallsIntoOthers() {
        let groups = [
            SongCredit.fixture(name: "A", category: nil),
            SongCredit.fixture(name: "B", category: "   "),
            SongCredit.fixture(name: "C", category: "")
        ].groupedByCategory()

        #expect(groups.count == 1)
        #expect(groups[0].category == "Others")
        #expect(groups[0].credits.count == 3)
    }

    @Test func headingsKeepFirstSeenOrder() {
        let groups = [
            SongCredit.fixture(category: "Zebra"),
            SongCredit.fixture(category: "Alpha"),
            SongCredit.fixture(category: "Zebra")
        ].groupedByCategory()
        #expect(groups.map(\.category) == ["Zebra", "Alpha"])
    }

    @Test func noCreditsMeansNoGroups() {
        #expect([SongCredit]().groupedByCategory().isEmpty)
    }
}
