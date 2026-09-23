import Foundation

let version = "1.0.0"

let usage = """
packagejam — force a real SwiftPM package resolution for an Xcode project

Works around a long-standing Xcode bug: xcodebuild -resolvePackageDependencies
doesn't reliably pick up a new tag for an already-resolved dependency, even
after deleting Package.resolved and clearing every SwiftPM cache — only
Xcode's own "Update to Latest Package Versions" menu item reliably does.
This drives plain `swift package resolve` (which has always worked correctly)
against the same dependency declarations, then writes the correct result
directly into the project's Package.resolved.

USAGE:
  packagejam [<path-to-Foo.xcodeproj>] [--dry-run]
  packagejam --version

  <path-to-Foo.xcodeproj>  Defaults to the sole .xcodeproj in the current
                            directory.
  --dry-run                 Show what would change without writing anything.
                             Exits 1 if an update is available, 0 if already
                             current — suitable for a CI check.

KNOWN LIMITATIONS:
  - Only .xcodeproj is supported directly, not a multi-project .xcworkspace
    whose package references are split across more than one project.
  - Local (path-based) package dependencies are ignored — there's nothing
    to resolve for those.
"""

func runCLI(arguments: [String]) -> Int32 {
    var explicitPath: String?
    var dryRun = false
    for argument in arguments {
        switch argument {
        case "--dry-run":
            dryRun = true
        case "--help", "-h":
            print(usage)
            return 0
        case "--version":
            print("packagejam \(version)")
            return 0
        default:
            explicitPath = argument
        }
    }

    do {
        let xcodeprojPath = try ProjectLocator.locateXcodeproj(explicitPath: explicitPath)
        let resolvedPath = ProjectLocator.resolvedFilePath(forXcodeproj: xcodeprojPath)

        print("Reading dependencies from \(xcodeprojPath)...")
        let dependencies = try ProjectFileReader.readDependencies(xcodeprojPath: xcodeprojPath)
        guard !dependencies.isEmpty else {
            print("No remote package dependencies found.")
            return 0
        }

        let beforeData = FileManager.default.contents(atPath: resolvedPath)
        let beforePins = (try? JSONSerialization.jsonObject(with: beforeData ?? Data())) as? [String: Any]
        let before = ChangeSummary.versionsByIdentity((beforePins?["pins"] as? [[String: Any]]) ?? [])

        print("Resolving \(dependencies.count) package(s) directly with SwiftPM " +
              "(bypassing Xcode's own resolver)...")
        let resolved = try Resolver.resolve(dependencies: dependencies)
        let afterPins = (resolved["pins"] as? [[String: Any]]) ?? []

        let changes = ChangeSummary.describeChanges(before: before, after: afterPins)
        guard !changes.isEmpty else {
            print("Already up to date.")
            return 0
        }

        for line in changes { print(line) }

        if dryRun {
            print("\n(--dry-run: not writing changes)")
            return 1
        }

        try ResolvedFileWriter.write(newPins: afterPins, toResolvedFileAt: resolvedPath)
        print("\nWrote \(resolvedPath)")
        return 0
    } catch let error as PackageJamError {
        FileHandle.standardError.write(Data((error.description + "\n").utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data(("Unexpected error: \(error)\n").utf8))
        return 1
    }
}

exit(runCLI(arguments: Array(CommandLine.arguments.dropFirst())))
