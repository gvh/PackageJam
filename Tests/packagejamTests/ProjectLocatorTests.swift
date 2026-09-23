import Foundation
import Testing
@testable import packagejam

@Suite struct ProjectLocatorTests {
    private func makeDirectory(containing names: [String]) throws -> String {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        for name in names {
            try FileManager.default.createDirectory(
                atPath: (directory as NSString).appendingPathComponent(name),
                withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func returnsTheExplicitPathUnchanged() throws {
        #expect(try ProjectLocator.locateXcodeproj(explicitPath: "/some/Foo.xcodeproj") == "/some/Foo.xcodeproj")
    }

    @Test func findsTheSoleXcodeprojInADirectory() throws {
        let directory = try makeDirectory(containing: ["Foo.xcodeproj", "Sources"])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let found = try ProjectLocator.locateXcodeproj(explicitPath: nil, in: directory)
        #expect(found == (directory as NSString).appendingPathComponent("Foo.xcodeproj"))
    }

    @Test func throwsWhenNoXcodeprojIsPresent() throws {
        let directory = try makeDirectory(containing: ["Sources"])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(throws: PackageJamError.self) {
            try ProjectLocator.locateXcodeproj(explicitPath: nil, in: directory)
        }
    }

    @Test func throwsWhenMoreThanOneXcodeprojIsPresent() throws {
        let directory = try makeDirectory(containing: ["B.xcodeproj", "A.xcodeproj"])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        #expect(throws: PackageJamError.self) {
            try ProjectLocator.locateXcodeproj(explicitPath: nil, in: directory)
        }
    }

    @Test func pointsAtTheImplicitWorkspacesResolvedFile() {
        #expect(ProjectLocator.resolvedFilePath(forXcodeproj: "/p/Foo.xcodeproj")
                == "/p/Foo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    }
}
