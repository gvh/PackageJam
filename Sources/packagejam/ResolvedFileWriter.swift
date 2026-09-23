import Foundation

/// Writes a freshly-resolved pin set into a project's real
/// `Package.resolved`.
public enum ResolvedFileWriter {
    /// Preserves the existing file's other top-level fields (notably
    /// `originHash`, schema v3's fingerprint of the *consumer's* manifest —
    /// which this tool never touches) verbatim, replacing only `pins`. If no
    /// file exists yet, starts from a bare v2-shaped document; Xcode fills
    /// in an `originHash` itself the next time it touches the file.
    public static func write(newPins: [Any], toResolvedFileAt path: String) throws {
        var root: [String: Any] = ["version": 2]
        if let existingData = FileManager.default.contents(atPath: path),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = existing
        }
        root["pins"] = newPins

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        // JSONSerialization escapes forward slashes (valid JSON, but not
        // what Xcode's own writer does) — undo that so a diff against a
        // file Xcode last touched shows only the actual pin changes.
        guard var text = String(data: data, encoding: .utf8) else {
            throw PackageJamError.resolveFailed("Couldn't encode the updated Package.resolved as UTF-8")
        }
        text = text.replacingOccurrences(of: "\\/", with: "/") + "\n"
        try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }
}
