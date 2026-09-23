/// A SwiftPM package dependency's version requirement, as declared in an
/// Xcode project (classic `project.pbxproj` or the newer JSON
/// `project.xcproj`). Modeling this explicitly — rather than jumping
/// straight to "just grab the latest tag" — matters: a project that
/// deliberately constrained a dependency (e.g. `.upToNextMinor`, to avoid
/// pulling in breaking changes) should still have that same constraint
/// honored, just resolved against whatever tags currently satisfy it.
public enum PackageRequirement: Equatable {
    case upToNextMajor(from: String)
    case upToNextMinor(from: String)
    case exact(String)
    case range(from: String, to: String)
    case branch(String)
    case revision(String)

    /// Renders the trailing argument of a `.package(url:, ...)` call for a
    /// synthetic `Package.swift` manifest.
    var manifestArgument: String {
        switch self {
        case .upToNextMajor(let version): return "from: \"\(version)\""
        case .upToNextMinor(let version): return ".upToNextMinor(from: \"\(version)\")"
        case .exact(let version): return "exact: \"\(version)\""
        case .range(let from, let to): return "\"\(from)\"..<\"\(to)\""
        case .branch(let name): return "branch: \"\(name)\""
        case .revision(let sha): return "revision: \"\(sha)\""
        }
    }
}

/// A single remote package dependency discovered in an Xcode project.
public struct PackageDependency: Equatable {
    public let url: String
    public let requirement: PackageRequirement

    public init(url: String, requirement: PackageRequirement) {
        self.url = url
        self.requirement = requirement
    }
}
