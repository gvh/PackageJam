import Testing
@testable import packagejam

@Suite struct PackageRequirementTests {
    @Test func upToNextMajorRendersFromArgument() {
        #expect(PackageRequirement.upToNextMajor(from: "1.2.3").manifestArgument == "from: \"1.2.3\"")
    }

    @Test func upToNextMinorRendersExplicitCall() {
        #expect(PackageRequirement.upToNextMinor(from: "1.2.3").manifestArgument == ".upToNextMinor(from: \"1.2.3\")")
    }

    @Test func exactRendersExactArgument() {
        #expect(PackageRequirement.exact("1.2.3").manifestArgument == "exact: \"1.2.3\"")
    }

    @Test func rangeRendersHalfOpenRangeOperator() {
        #expect(PackageRequirement.range(from: "1.0.0", to: "2.0.0").manifestArgument == "\"1.0.0\"..<\"2.0.0\"")
    }

    @Test func branchRendersBranchArgument() {
        #expect(PackageRequirement.branch("main").manifestArgument == "branch: \"main\"")
    }

    @Test func revisionRendersRevisionArgument() {
        #expect(PackageRequirement.revision("abc123").manifestArgument == "revision: \"abc123\"")
    }
}
