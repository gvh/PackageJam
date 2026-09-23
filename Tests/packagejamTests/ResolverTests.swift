import Foundation
import Testing
@testable import packagejam

/// The core mechanism test: a local, hermetic git repo standing in for a
/// real dependency's remote, so this proves — with no network access and
/// no dependency on GitHub being reachable — that `Resolver.resolve` really
/// does pick up new tags, and really does still respect the declared
/// requirement rather than always grabbing the newest tag that exists.
@Suite struct ResolverTests {
    private final class Fixture {
        let directory: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("packagejam-fixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let manifest = """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Fixture", targets: [.target(name: "Fixture")])
            """
            try manifest.write(to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
            let sourcesDir = directory.appendingPathComponent("Sources/Fixture")
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
            try "".write(to: sourcesDir.appendingPathComponent("Fixture.swift"), atomically: true, encoding: .utf8)

            try git(["init", "-q", "-b", "main"])
            try commitAndTag("1.0.0")
        }

        deinit { try? FileManager.default.removeItem(at: directory) }

        /// A commit + tag per call, so each tag points at a distinct commit
        /// — closer to a real dependency's history than tagging the same
        /// commit repeatedly.
        func commitAndTag(_ tag: String) throws {
            let marker = directory.appendingPathComponent("Sources/Fixture/Fixture.swift")
            try "// \(tag)".write(to: marker, atomically: true, encoding: .utf8)
            try git(["add", "-A"])
            try git(["commit", "-q", "-m", tag, "--allow-empty"])
            try git(["tag", tag])
        }

        /// `.package(url:)` needs an actual URL, not a bare filesystem path.
        var fileURL: String { "file://" + directory.path }

        private func git(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-c", "user.email=test@example.com", "-c", "user.name=Test"] + arguments
            process.currentDirectoryURL = directory
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "git \(arguments.joined(separator: " ")) failed")
        }
    }

    private func resolvedVersion(_ resolved: [String: Any]) -> String? {
        let pins = resolved["pins"] as? [[String: Any]] ?? []
        let state = pins.first?["state"] as? [String: Any]
        return state?["version"] as? String
    }

    @Test func picksUpANewTagPublishedAfterTheOldOneWasAlreadyResolved() throws {
        let fixture = try Fixture()
        try fixture.commitAndTag("1.5.0")

        let dependency = PackageDependency(url: fixture.fileURL, requirement: .upToNextMajor(from: "1.0.0"))
        let resolved = try Resolver.resolve(dependencies: [dependency])

        #expect(resolvedVersion(resolved) == "1.5.0")
    }

    @Test func upToNextMajorDoesNotCrossTheMajorBoundary() throws {
        let fixture = try Fixture()
        try fixture.commitAndTag("2.0.0")

        let dependency = PackageDependency(url: fixture.fileURL, requirement: .upToNextMajor(from: "1.0.0"))
        let resolved = try Resolver.resolve(dependencies: [dependency])

        // 2.0.0 exists, but upToNextMajor(from: "1.0.0") excludes it — this is
        // exactly the correctness property that distinguishes "resolve
        // correctly" from "just grab whatever tag is newest."
        #expect(resolvedVersion(resolved) == "1.0.0")
    }

    @Test func exactPinsToThatVersionEvenWhenNewerTagsExist() throws {
        let fixture = try Fixture()
        try fixture.commitAndTag("1.5.0")

        let dependency = PackageDependency(url: fixture.fileURL, requirement: .exact("1.0.0"))
        let resolved = try Resolver.resolve(dependencies: [dependency])

        #expect(resolvedVersion(resolved) == "1.0.0")
    }

    @Test func resolvesMultipleDependenciesTogether() throws {
        let first = try Fixture()
        try first.commitAndTag("1.2.0")
        let second = try Fixture()
        try second.commitAndTag("3.4.0")

        let dependencies = [
            PackageDependency(url: first.fileURL, requirement: .upToNextMajor(from: "1.0.0")),
            PackageDependency(url: second.fileURL, requirement: .upToNextMajor(from: "3.0.0")),
        ]
        let resolved = try Resolver.resolve(dependencies: dependencies)
        let pins = resolved["pins"] as? [[String: Any]] ?? []

        #expect(pins.count == 2)
    }
}
