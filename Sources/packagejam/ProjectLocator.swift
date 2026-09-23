import Foundation

public enum ProjectLocator {
    /// Finds the `.xcodeproj` to operate on: the explicit path if one was
    /// given, otherwise the sole `.xcodeproj` in `directory` — mirroring
    /// `xcodebuild`'s own auto-discovery convention so this feels familiar.
    public static func locateXcodeproj(explicitPath: String?, in directory: String = ".") throws -> String {
        if let explicitPath {
            return explicitPath
        }
        let candidates = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()
        switch candidates.count {
        case 0: throw PackageJamError.noXcodeprojFound
        case 1: return (directory as NSString).appendingPathComponent(candidates[0])
        default: throw PackageJamError.multipleXcodeprojsFound(candidates)
        }
    }

    /// Xcode always maintains an implicit workspace inside every
    /// `.xcodeproj`, and that's where its resolved package pins live —
    /// regardless of whether the project is also embedded in some other,
    /// external `.xcworkspace`.
    ///
    /// Known limitation: a multi-project `.xcworkspace` whose package
    /// references are split across more than one constituent `.xcodeproj`
    /// isn't supported — point PackageJam at each `.xcodeproj` individually.
    public static func resolvedFilePath(forXcodeproj xcodeprojPath: String) -> String {
        (xcodeprojPath as NSString).appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    }
}
