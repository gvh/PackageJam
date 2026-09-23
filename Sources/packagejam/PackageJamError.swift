public enum PackageJamError: Error, CustomStringConvertible, Equatable {
    case noXcodeprojFound
    case multipleXcodeprojsFound([String])
    case noProjectFile(String)
    case cannotReadProjectFile(String)
    case unsupportedRequirement(String)
    case resolveFailed(String)

    public var description: String {
        switch self {
        case .noXcodeprojFound:
            return "No .xcodeproj found in the current directory. Pass one explicitly: packagejam path/to/Foo.xcodeproj"
        case .multipleXcodeprojsFound(let names):
            return "Multiple .xcodeproj found (\(names.joined(separator: ", "))) — specify which one: packagejam path/to/Foo.xcodeproj"
        case .noProjectFile(let path):
            return "Neither project.xcproj nor project.pbxproj found inside \(path)"
        case .cannotReadProjectFile(let path):
            return "Couldn't parse \(path) — is plutil available, and is this a valid Xcode project?"
        case .unsupportedRequirement(let detail):
            return "Found a package dependency with a version requirement PackageJam doesn't recognize yet (\(detail)). " +
                "Please file an issue at https://github.com/gvh/PackageJam/issues with your project's dependency declaration."
        case .resolveFailed(let detail):
            return "swift package resolve failed:\n\(detail)"
        }
    }
}
