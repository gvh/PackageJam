import Foundation

/// Resolves a set of package dependencies for real, by driving a throwaway
/// SwiftPM package in a temp directory rather than Xcode's own resolution
/// path.
///
/// Why this works: `xcodebuild -resolvePackageDependencies` doesn't
/// reliably pick up a new tag for an already-resolved dependency — even
/// after deleting `Package.resolved` and clearing every SwiftPM cache. But
/// plain `swift package resolve`, run against a manifest declaring the same
/// dependencies, always has. The bug is specifically in the .xcodeproj-
/// embedded resolution path, not in SwiftPM's resolver itself — so instead
/// of fighting the broken path, this routes around it entirely and writes
/// the correct, independently-verified result straight into the file Xcode
/// reads on its next build.
public enum Resolver {
    /// Returns the decoded contents of the synthetic package's resulting
    /// `Package.resolved` — i.e. the full, correct pin set (direct and
    /// transitive) for `dependencies`.
    public static func resolve(dependencies: [PackageDependency]) throws -> [String: Any] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("packagejam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeSyntheticManifest(dependencies, to: tempDir)

        let result = try run("/usr/bin/swift", ["package", "--package-path", tempDir.path, "resolve"])
        guard result.exitCode == 0 else {
            throw PackageJamError.resolveFailed(result.output)
        }

        let resolvedURL = tempDir.appendingPathComponent("Package.resolved")
        let data = try Data(contentsOf: resolvedURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PackageJamError.resolveFailed("Package.resolved wasn't valid JSON")
        }
        return json
    }

    // A dependency declared but never referenced by any target still gets
    // resolved and pinned — verified directly before relying on it here, so
    // there's no need to guess at each dependency's actual product name(s).
    static func writeSyntheticManifest(_ dependencies: [PackageDependency], to dir: URL) throws {
        let packageDeps = dependencies
            .map { "        .package(url: \"\($0.url)\", \($0.requirement.manifestArgument))" }
            .joined(separator: ",\n")
        let manifest = """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "packagejam-scratch",
            dependencies: [
        \(packageDeps)
            ],
            targets: [.target(name: "Scratch")]
        )
        """
        try manifest.write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let sourcesDir = dir.appendingPathComponent("Sources/Scratch")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try "".write(to: sourcesDir.appendingPathComponent("Scratch.swift"), atomically: true, encoding: .utf8)
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
