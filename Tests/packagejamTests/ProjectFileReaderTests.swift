import Foundation
import Testing
@testable import packagejam

@Suite struct ProjectFileReaderTests {
    // MARK: - Xcode 26+ JSON project format

    @Test func jsonProjectParsesUpToNextMajor() throws {
        let json = """
        {
          "packages": [
            { "kind": "remote", "repository": "https://github.com/example/SomePackage",
              "version": { "up-to-next-major-version": "2.0.19" } }
          ]
        }
        """
        let deps = try ProjectFileReader.parseJSONProject(Data(json.utf8))
        #expect(deps == [PackageDependency(url: "https://github.com/example/SomePackage", requirement: .upToNextMajor(from: "2.0.19"))])
    }

    @Test func jsonProjectIgnoresNonRemotePackages() throws {
        let json = """
        {
          "packages": [
            { "kind": "local", "path": "../SomeLocalPackage" }
          ]
        }
        """
        let deps = try ProjectFileReader.parseJSONProject(Data(json.utf8))
        #expect(deps.isEmpty)
    }

    @Test func jsonProjectThrowsOnUnrecognizedRequirement() {
        let dict: [String: Any] = ["something-unknown": "1.0.0"]
        #expect(throws: PackageJamError.self) {
            try ProjectFileReader.parseJSONRequirement(dict)
        }
    }

    // MARK: - Classic pbxproj format (as JSON, via plutil)

    @Test func classicProjectParsesUpToNextMajorVersion() throws {
        let json: [String: Any] = [
            "objects": [
                "ABC123": [
                    "isa": "XCRemoteSwiftPackageReference",
                    "repositoryURL": "https://github.com/example/SomePackage",
                    "requirement": ["kind": "upToNextMajorVersion", "minimumVersion": "2.0.19"],
                ],
                "DEF456": [
                    "isa": "PBXFileReference",
                    "path": "SomeFile.swift",
                ],
            ]
        ]
        let deps = try ProjectFileReader.parseClassicProject(json)
        #expect(deps == [PackageDependency(url: "https://github.com/example/SomePackage", requirement: .upToNextMajor(from: "2.0.19"))])
    }

    @Test func classicProjectParsesExactVersion() throws {
        let requirement = try ProjectFileReader.parsePbxprojRequirement(["kind": "exactVersion", "version": "1.2.3"])
        #expect(requirement == .exact("1.2.3"))
    }

    @Test func classicProjectParsesBranch() throws {
        let requirement = try ProjectFileReader.parsePbxprojRequirement(["kind": "branch", "branch": "main"])
        #expect(requirement == .branch("main"))
    }

    @Test func classicProjectParsesRevision() throws {
        let requirement = try ProjectFileReader.parsePbxprojRequirement(["kind": "revision", "revision": "abc123"])
        #expect(requirement == .revision("abc123"))
    }

    @Test func classicProjectParsesVersionRange() throws {
        let requirement = try ProjectFileReader.parsePbxprojRequirement([
            "kind": "versionRange", "minimumVersion": "1.0.0", "maximumVersion": "2.0.0",
        ])
        #expect(requirement == .range(from: "1.0.0", to: "2.0.0"))
    }

    @Test func classicProjectThrowsOnUnrecognizedKind() {
        #expect(throws: PackageJamError.self) {
            try ProjectFileReader.parsePbxprojRequirement(["kind": "somethingNew"])
        }
    }
}
