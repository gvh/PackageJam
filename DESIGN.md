# PackageJam: design and reasoning

This document explains *why* PackageJam exists, *why* it's built the way it
is, and what its safety properties are. It's written for two audiences at
once: a human engineer evaluating or extending the tool, and a future AI
coding session picking this project back up cold. Where a decision could
plausibly have gone another way, the rejected alternative and the reason
it lost are recorded — that's usually the part that's expensive to
re-derive and cheap to just write down.

If you only need to *run* the tool, see [OPERATIONS.md](OPERATIONS.md)
instead. This file is about why it's built this way.

## 1. The bug this tool routes around

**Symptom:** you push a new version tag to a SwiftPM package. A consuming
Xcode project has that package pinned to an older version via
`.upToNextMajor(from:)` or similar — a requirement the new tag clearly
satisfies. You run:

```
xcodebuild -resolvePackageDependencies -project Foo.xcodeproj -scheme Foo
```

expecting it to update `Package.resolved` to the new tag. **It doesn't.**
The pin stays on the old version.

**What was tried, and ruled out, before concluding this is an Xcode bug:**

- Deleting `Package.resolved` entirely and re-running the resolve. No
  change — it regenerates a resolved file pinned to the *same* old
  version, as if it never looked past the previous pin.
- Clearing every SwiftPM cache Xcode maintains:
  `~/Library/Caches/org.swift.swiftpm/{repositories,manifests,package-metadata}`.
  No change.
- Deleting the project's DerivedData. No change.
- Hypothesizing that `Package.resolved`'s schema-v3 `originHash` field
  (a fingerprint of the *consuming* manifest's own inputs) was somehow
  gating re-resolution. Investigated directly — it isn't; it's not an
  active resolution-skip mechanism at all, just a diagnostic fingerprint.

**What does work:** in Xcode's GUI, **File → Packages → Update to Latest
Package Versions**. That command, and *only* that command, reliably
re-resolves to the new tag. It shares no visible code path with
`xcodebuild -resolvePackageDependencies` — whatever it does differently
isn't exposed as a flag or scriptable in any way.

**What also, independently, works:** plain `swift package resolve`, run
outside of Xcode and `xcodebuild` entirely, against a manifest declaring
the same dependency and requirement. This was verified repeatedly during
this tool's development, across several real version bumps, and it never
once failed to find the newest tag satisfying the requirement.

**Conclusion:** the bug is specifically in the `.xcodeproj`-embedded
resolution path that `xcodebuild` drives (whatever that path is
internally — it isn't SwiftPM's own resolver, since that resolver behaves
correctly when invoked directly). This was reported to Apple as
**FB16108036**, confirmed still present as of Xcode 27.2 (27B5019j) at
time of writing. There's a public Apple Developer Forums thread
describing the same symptom independently, which is where the "only the
GUI action works" finding was cross-checked against someone else hitting
the same wall.

Because this is Xcode's own bug and not a SwiftPM defect, and because
there's no documented flag or environment variable that changes
`xcodebuild`'s behavior here, there is no legitimate command-line fix —
only a workaround. That's what PackageJam is.

## 2. The workaround, in one sentence

Read the dependency declarations straight out of the `.xcodeproj` file,
resolve them for real by driving `swift package resolve` against a
throwaway manifest that declares the same dependencies, and write that
verified result directly into the project's real `Package.resolved` —
bypassing `xcodebuild`'s broken resolution path entirely.

This is not a hack that guesses at version numbers or scrapes a registry.
It performs an actual, correct SwiftPM resolution (the same algorithm
Xcode's GUI action ultimately triggers) and persists its output in the
exact file format and location Xcode itself reads on the next build.

## 3. Architecture

```
main.swift
  ├─ ProjectLocator        find the .xcodeproj, find its Package.resolved
  ├─ ProjectFileReader      read declared dependencies (both project formats)
  ├─ Resolver               do a real `swift package resolve` in a temp dir
  ├─ ChangeSummary          diff old pins vs new pins, for human-readable output
  └─ ResolvedFileWriter     write the new pins into the real Package.resolved
```

Supporting types: `PackageRequirement` / `PackageDependency`
(`PackageRequirement.swift`) model a dependency's version constraint;
`PackageJamError` (`PackageJamError.swift`) is the single error type,
each case carrying its own actionable message.

### 3.1 `ProjectLocator`

Two responsibilities: find the `.xcodeproj` (explicit path, or the sole
one in the current directory — mirroring `xcodebuild`'s own
auto-discovery convention), and compute the path to its
`Package.resolved`.

The important thing to know here: **Xcode always maintains an implicit
workspace inside every `.xcodeproj`**, at
`<xcodeproj>/project.xcworkspace/`, and *that's* where resolved package
pins live — at
`<xcodeproj>/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` —
regardless of whether the project is also embedded in some other,
external `.xcworkspace` you opened it through. This was confirmed
directly against a real app project during
development, not assumed from documentation.

**Known limitation, by design, not oversight:** a multi-project
`.xcworkspace` whose package references are split across more than one
constituent `.xcodeproj` isn't handled as a unit — point PackageJam at
each `.xcodeproj` individually. Handling the external-workspace case
would require locating and merging multiple resolved files, which adds
real complexity for a case that hasn't come up yet. Per "as simple as
possible, but no simpler," this is deferred until someone actually needs
it.

### 3.2 `ProjectFileReader`

Xcode has *two* project file formats in the wild, and this tool must read
dependency declarations out of either:

- **Classic `project.pbxproj`** (property list, historically written as
  ASCII plist, now usually binary or XML plist). Read by shelling out to
  `plutil -convert json -o - <path>` and parsing the JSON it emits — this
  avoids needing a bespoke plist/pbxproj parser. Dependency declarations
  appear as objects with `isa: "XCRemoteSwiftPackageReference"`, holding
  `repositoryURL` and a `requirement` dictionary.
- **New JSON `project.xcproj`**, introduced in Xcode 26/27. Declarations
  appear directly as JSON in a top-level `"packages"` array, each entry
  shaped like
  `{"kind": "remote", "repository": <url>, "version": {<requirement>}}`.

`readDependencies(xcodeprojPath:)` checks for `project.xcproj` first (the
newer format), falling back to `project.pbxproj`.

**Confirmed vs. inferred field names — important caveat.** For the JSON
format, only the `up-to-next-major-version` key was directly observed in
a real Xcode 27 project (the one this tool was built against). The other
keys in `parseJSONRequirement` — `up-to-next-minor-version`,
`exact-version`, `branch`, `revision`, `range` with
`minimum-version`/`maximum-version` — are *inferred* by consistent
kebab-casing of the confirmed key, not individually confirmed. Likewise
for the classic pbxproj format, `upToNextMajorVersion`/`minimumVersion`,
`branch`, and `revision` are confirmed from real projects; `exactVersion`'s
`version` field and `versionRange`'s two bounds are inferred by naming
convention. This is called out in code comments at each parse site
(`ProjectFileReader.swift`), not just here — if you ever hit
`PackageJamError.unsupportedRequirement` for a dependency that *does* have
a recognizable requirement kind, the fix is almost certainly correcting
one of these inferred field names, not adding new logic.

Only *direct* dependencies are read. `Resolver` resolves the full
transitive graph starting from them, exactly as Xcode itself would — there
is no need to walk transitive dependencies here.

### 3.3 `Resolver`

The core mechanism. `resolve(dependencies:)`:

1. Creates a fresh temp directory.
2. Writes a synthetic `Package.swift` there
   (`writeSyntheticManifest`) declaring exactly the given dependencies,
   with a single dummy target, `"Scratch"`, that depends on nothing (no
   product names need to be known or guessed).
3. Shells out to `swift package --package-path <tempdir> resolve`.
4. Reads back the `Package.resolved` that command produced and returns it
   parsed as JSON.
5. Deletes the temp directory (`defer`).

Two things worth knowing if you're re-deriving this from scratch:

- **A dependency declared but never referenced by any target still gets
  resolved and pinned.** This was verified directly (not assumed) before
  relying on it — it means the synthetic manifest doesn't need to guess
  each dependency's actual product name(s), which it has no way to know
  from an Xcode project's `XCRemoteSwiftPackageReference` alone (product
  usage is recorded elsewhere, on the target's
  `XCSwiftPackageProductDependency` entries, which this tool deliberately
  doesn't parse).
- **The target name is `"Scratch"`**, not something more evocative, only
  because Swift module names can't contain hyphens and this needed to be
  short and obviously disposable.

### 3.4 `ResolvedFileWriter`

Writes the new pins into the real project's `Package.resolved`. Three
non-obvious things happen here, each fixed after being caught in a live
smoke test against a real app project with a broken pin, not
speculatively:

- **Preserves every other top-level field, especially `originHash`.**
  `originHash` is schema v3's fingerprint of the *consuming* project's own
  manifest inputs — not of dependency state — and this tool never
  computes or touches it. Only `pins` is replaced; if no file exists yet,
  it starts from a bare `{"version": 2}` document and lets Xcode compute
  an `originHash` itself the next time it touches the file.
- **Un-escapes forward slashes.** `JSONSerialization` escapes `/` as `\/`
  by default — valid JSON, but not what Xcode's own writer produces, so a
  diff against a file Xcode last touched would show every URL as changed
  even when it wasn't. Fixed with a post-serialization string replace.
- **Appends a trailing newline** to match Xcode's own file convention.

### 3.5 `ChangeSummary`

Pure, testable diffing logic, no I/O: given the old pin identities/
versions and the new pin set, produce human-readable
`"identity: old → new"` / `"identity: (new) version"` lines, sorted by
identity for stable output. Used both for the printed summary and to
decide whether there's anything to report at all (an empty list means
"already up to date," and `main.swift` skips writing the file in that
case — the write is skipped, not just under-reported, so a `--dry-run`
run and a real run agree on when there's nothing to do).

### 3.6 `main.swift`

Wires the above together, handles `--dry-run` (report only, exit `1` if
an update was available so it's usable as a CI gate, `0` if already
current) and `--help`, and is the only place that talks to stdout/stderr
directly.

## 4. Safety properties

These are the properties that make it reasonable to run this tool against
a real project without asking for confirmation each time (see
[OPERATIONS.md](OPERATIONS.md) §5 for the actual authorization statement):

- **Never writes to `Package.swift`, `project.pbxproj`, or
  `project.xcproj`.** Those are only ever read.
- **Only writes to `Package.resolved`**, and only the `pins` key within
  it — every other field of an existing file is preserved verbatim.
- **The write is exactly what Xcode's own "Update to Latest Package
  Versions" would have produced** (same resolver, different entry point),
  not a heuristic approximation.
- **Idempotent.** Running it twice in a row with no new tags published in
  between produces "Already up to date" and touches nothing the second
  time.
- **`--dry-run` never writes anything**, and its exit code distinguishes
  "already current" (0) from "update available" (1) — safe to run
  speculatively or wire into CI.
- **All resolution work happens in a disposable temp directory**, deleted
  before the process returns; nothing is left behind on disk regardless of
  success or failure.
- **A local, reversible filesystem edit.** The result is one file, inside
  a git-tracked project; `git diff`/`git checkout --` on it is a complete,
  trivial undo.

## 5. Testing strategy

27 tests across 5 suites, run with `swift test`. The interesting one is
`ResolverTests`, because it's the only suite that exercises the actual
mechanism (a real `swift package resolve` invocation) rather than pure
logic:

- Each test builds a **hermetic local git repository** in a temp directory
  (a real `git init`, real commits, real `git tag`), then hands
  `Resolver.resolve` a `PackageDependency` whose URL is `file://` +
  that directory's path. Git supports fetching from local non-bare
  repositories over the `file://` transport, and SwiftPM's own resolver
  doesn't care that the "remote" is local — this is the standard pattern
  SwiftPM's own test suite uses for exactly this reason: no network
  access required, no dependency on GitHub being reachable, fully
  deterministic.
- `picksUpANewTagPublishedAfterTheOldOneWasAlreadyResolved` — proves the
  core claim: a tag added *after* an initial resolve is still found.
- `upToNextMajorDoesNotCrossTheMajorBoundary` and
  `exactPinsToThatVersionEvenWhenNewerTagsExist` — prove the tool
  *respects* the declared requirement rather than always grabbing
  whichever tag is newest. This distinction matters: a tool that just
  fetched the latest tag regardless of constraints would silently pull
  breaking changes into a project that deliberately used
  `upToNextMinor`/`exact` to avoid exactly that.
- `resolvesMultipleDependenciesTogether` — sanity check that multiple
  independent dependencies resolve together into one pin set, as they
  would in a real project.

The other four suites (`PackageRequirementTests`, `ProjectFileReaderTests`,
`ResolvedFileWriterTests`, `ChangeSummaryTests`) are conventional
input/output unit tests with no process execution, covering both project
formats' parsers, all six requirement kinds, and the file-writing edge
cases (preserving `originHash`, starting fresh, slash-escaping, trailing
newline).

## 6. Known limitations (and why they're acceptable)

- **Multi-project `.xcworkspace` isn't handled as a unit.** See §3.1.
  Workaround: run PackageJam once per constituent `.xcodeproj`.
- **Local (path-based) package dependencies are silently skipped** — both
  project-format parsers only recognize `kind: "remote"` /
  `XCRemoteSwiftPackageReference` entries. There's nothing to resolve for
  a local dependency (no version, no tag), so this is correct behavior,
  not a gap.
- **Some JSON-project-format requirement field names are inferred, not
  confirmed** (see §3.2). If one is wrong, the failure mode is a clear
  `unsupportedRequirement` error naming the exact dictionary that didn't
  parse — not a silent misread.
- **No product-usage checking.** If an Xcode project declares a package
  dependency but no target actually links to any of its products, that
  dependency is still resolved and pinned (see §3.3) — matching what
  Xcode itself would do, not a bug.
