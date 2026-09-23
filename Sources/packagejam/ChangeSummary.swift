import Foundation

/// Human-readable "before → after" reporting, comparing two pin sets by
/// package identity.
public enum ChangeSummary {
    /// Maps each pin's `identity` to a display string for its resolved
    /// state (version, or branch/revision for non-version requirements).
    public static func versionsByIdentity(_ pins: [[String: Any]]) -> [String: String] {
        var result: [String: String] = [:]
        for pin in pins {
            guard let identity = pin["identity"] as? String else { continue }
            let state = pin["state"] as? [String: Any]
            result[identity] = (state?["version"] as? String)
                ?? (state?["branch"] as? String)
                ?? (state?["revision"] as? String)
                ?? "?"
        }
        return result
    }

    /// One line per changed/new package, sorted by identity for stable output.
    public static func describeChanges(before: [String: String], after: [[String: Any]]) -> [String] {
        let afterVersions = versionsByIdentity(after)
        return afterVersions.sorted(by: { $0.key < $1.key }).compactMap { identity, newVersion in
            guard before[identity] != newVersion else { return nil }
            if let oldVersion = before[identity] {
                return "  \(identity): \(oldVersion) \u{2192} \(newVersion)"
            }
            return "  \(identity): (new) \(newVersion)"
        }
    }
}
