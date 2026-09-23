import Foundation

/// Reads the direct remote package dependencies an Xcode project declares.
///
/// Only direct dependencies are needed here — `Resolver` resolves the full
/// transitive graph from them, the same as Xcode itself would.
public enum ProjectFileReader {
    public static func readDependencies(xcodeprojPath: String) throws -> [PackageDependency] {
        let jsonPath = (xcodeprojPath as NSString).appendingPathComponent("project.xcproj")
        let pbxprojPath = (xcodeprojPath as NSString).appendingPathComponent("project.pbxproj")

        if FileManager.default.fileExists(atPath: jsonPath) {
            return try readFromJSONProject(at: jsonPath)
        } else if FileManager.default.fileExists(atPath: pbxprojPath) {
            return try readFromClassicProject(at: pbxprojPath)
        } else {
            throw PackageJamError.noProjectFile(xcodeprojPath)
        }
    }

    // MARK: - Xcode 26+ JSON project format (project.xcproj)

    static func readFromJSONProject(at path: String) throws -> [PackageDependency] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try parseJSONProject(data)
    }

    /// Exposed at `Data` granularity (rather than only a file path) so tests
    /// can exercise this against an in-memory fixture.
    static func parseJSONProject(_ data: Data) throws -> [PackageDependency] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [[String: Any]] else {
            return []
        }
        return try packages.compactMap { entry -> PackageDependency? in
            guard entry["kind"] as? String == "remote",
                  let url = entry["repository"] as? String,
                  let versionDict = entry["version"] as? [String: Any] else {
                return nil
            }
            return PackageDependency(url: url, requirement: try parseJSONRequirement(versionDict))
        }
    }

    // The field names below are confirmed for "up-to-next-major-version"
    // (observed directly in a real Xcode 27 project.xcproj this tool was
    // built against). The others are inferred by consistent kebab-casing of
    // the same convention and haven't been individually confirmed against a
    // real project — if one of them throws unsupportedRequirement for you,
    // please file an issue with the actual JSON so it can be fixed for real.
    static func parseJSONRequirement(_ dict: [String: Any]) throws -> PackageRequirement {
        if let version = dict["up-to-next-major-version"] as? String {
            return .upToNextMajor(from: version)
        }
        if let version = dict["up-to-next-minor-version"] as? String {
            return .upToNextMinor(from: version)
        }
        if let version = dict["exact-version"] as? String {
            return .exact(version)
        }
        if let branch = dict["branch"] as? String {
            return .branch(branch)
        }
        if let revision = dict["revision"] as? String {
            return .revision(revision)
        }
        if let range = dict["range"] as? [String: Any],
           let from = range["minimum-version"] as? String,
           let to = range["maximum-version"] as? String {
            return .range(from: from, to: to)
        }
        throw PackageJamError.unsupportedRequirement(String(describing: dict))
    }

    // MARK: - Classic pbxproj format (project.pbxproj)

    static func readFromClassicProject(at path: String) throws -> [PackageDependency] {
        let json = try runPlutilToJSON(path: path)
        return try parseClassicProject(json)
    }

    static func parseClassicProject(_ json: [String: Any]) throws -> [PackageDependency] {
        guard let objects = json["objects"] as? [String: Any] else { return [] }
        return try objects.values.compactMap { value -> PackageDependency? in
            guard let object = value as? [String: Any],
                  object["isa"] as? String == "XCRemoteSwiftPackageReference",
                  let url = object["repositoryURL"] as? String,
                  let requirementDict = object["requirement"] as? [String: Any] else {
                return nil
            }
            return PackageDependency(url: url, requirement: try parsePbxprojRequirement(requirementDict))
        }
    }

    // Confirmed shape: {kind, minimumVersion} for upToNextMajorVersion/
    // upToNextMinorVersion, {kind, branch} for branch, {kind, revision} for
    // revision. exactVersion's value field and versionRange's two bounds are
    // inferred by the same naming convention and not individually confirmed.
    static func parsePbxprojRequirement(_ dict: [String: Any]) throws -> PackageRequirement {
        guard let kind = dict["kind"] as? String else {
            throw PackageJamError.unsupportedRequirement(String(describing: dict))
        }
        switch kind {
        case "upToNextMajorVersion":
            guard let version = dict["minimumVersion"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .upToNextMajor(from: version)
        case "upToNextMinorVersion":
            guard let version = dict["minimumVersion"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .upToNextMinor(from: version)
        case "exactVersion":
            guard let version = dict["version"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .exact(version)
        case "versionRange":
            guard let from = dict["minimumVersion"] as? String, let to = dict["maximumVersion"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .range(from: from, to: to)
        case "branch":
            guard let branch = dict["branch"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .branch(branch)
        case "revision":
            guard let revision = dict["revision"] as? String else {
                throw PackageJamError.unsupportedRequirement(String(describing: dict))
            }
            return .revision(revision)
        default:
            throw PackageJamError.unsupportedRequirement(kind)
        }
    }

    private static func runPlutilToJSON(path: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-convert", "json", "-o", "-", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PackageJamError.cannotReadProjectFile(path)
        }
        return json
    }
}
