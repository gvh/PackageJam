import Testing
@testable import packagejam

@Suite struct ChangeSummaryTests {
    @Test func reportsAChangedVersion() {
        let before = ["somepackage": "2.0.35"]
        let after: [[String: Any]] = [["identity": "somepackage", "state": ["version": "2.0.41"]]]
        #expect(ChangeSummary.describeChanges(before: before, after: after) == ["  somepackage: 2.0.35 \u{2192} 2.0.41"])
    }

    @Test func reportsANewDependencyWithNoPriorPin() {
        let after: [[String: Any]] = [["identity": "brandnew", "state": ["version": "1.0.0"]]]
        #expect(ChangeSummary.describeChanges(before: [:], after: after) == ["  brandnew: (new) 1.0.0"])
    }

    @Test func reportsNothingWhenUnchanged() {
        let before = ["somepackage": "2.0.41"]
        let after: [[String: Any]] = [["identity": "somepackage", "state": ["version": "2.0.41"]]]
        #expect(ChangeSummary.describeChanges(before: before, after: after).isEmpty)
    }

    @Test func fallsBackToBranchOrRevisionWhenNoVersion() {
        let after: [[String: Any]] = [["identity": "onbranch", "state": ["branch": "main"]]]
        #expect(ChangeSummary.versionsByIdentity(after) == ["onbranch": "main"])
    }
}
