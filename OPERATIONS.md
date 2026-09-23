# PackageJam: operations runbook

This is the practical "how do I actually run this" doc. For *why* it's
built this way, see [DESIGN.md](DESIGN.md).

## 0. Quick start for a future session (human or AI)

If you (or a future Claude session) land here because an Xcode project's
package pin is stuck on an old version and `xcodebuild
-resolvePackageDependencies` isn't fixing it — that's the known, unfixed
Xcode bug FB16108036 (see DESIGN.md §1). Don't spend time re-diagnosing
it, don't clear caches, don't delete DerivedData, and don't ask the user
to click through Xcode's GUI.

**First, one disambiguation, because it's an easy wrong turn:**
PackageJam is a standalone CLI tool, not a Swift package dependency.
Don't add it to the affected project via File → Add Package Dependencies
in Xcode — it has no library product, so there's nothing there for that
project to link against. It's a separate tool you build once and run
from the command line against the project; it never becomes part of the
project itself.

If you don't already have a local clone (check `~/code/PackageJam`
first — it may already be there from a previous session):

```
git clone https://github.com/gvh/PackageJam.git ~/code/PackageJam
```

Then, regardless of whether you just cloned it or it was already there:

```
cd ~/code/PackageJam && swift build -c release
~/code/PackageJam/.build/release/packagejam /path/to/Foo.xcodeproj
```

That's it. If it prints `Already up to date.`, the pin genuinely is
current and the problem is elsewhere. If it prints one or more
`identity: old → new` lines, the fix already happened — the real
`Package.resolved` has been rewritten, and the *next* build of that
project (Xcode or `xcodebuild`) will use the corrected pin. No further
Xcode-side action is needed; specifically, there is no need to also run
`xcodebuild -resolvePackageDependencies` or ask the user to click
"Update to Latest Package Versions" afterward — that step is exactly what
this tool replaces.

Running this against a project's `Package.resolved` is pre-authorized —
see §5 below for the exact scope of that authorization and what's still
outside it (in particular: committing the result).

## 1. Building

```
cd ~/code/PackageJam
swift build -c release
```

Binary lands at `~/code/PackageJam/.build/release/packagejam`. Debug
builds (`swift build`, no `-c release`) also work and are fine for
one-off use — release is only worth it if you're calling this often
enough that startup time matters, which it doesn't in practice (the whole
run, including the real `swift package resolve`, is seconds).

There's nothing to install system-wide unless you want the convenience of
a bare `packagejam` on `PATH` — e.g. symlinking the release binary into
`~/bin` — but that's optional and hasn't been done as part of
building this tool; do it only if the user asks for it, since it's a
change outside `~/code/PackageJam` itself.

Rebuilding after pulling PackageJam source changes: same command, just
run it again. `swift build` is incremental.

## 2. Running it against a real project

No arguments needed if you're `cd`'d into the directory containing the
`.xcodeproj` and there's only one there; otherwise pass the path
explicitly:

```
~/code/PackageJam/.build/release/packagejam ~/code/MyApp/MyApp.xcodeproj
```

Example output when `SomePackage` had a stale pin (real output from a
live smoke test run during development, with names anonymized):

```
Reading dependencies from /Users/you/code/MyApp/MyApp.xcodeproj...
Resolving 1 package(s) directly with SwiftPM (bypassing Xcode's own resolver)...
  somepackage: 2.0.35 → 2.0.41

Wrote /Users/you/code/MyApp/MyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

If nothing needs updating:

```
Reading dependencies from /Users/you/code/MyApp/MyApp.xcodeproj...
Resolving 1 package(s) directly with SwiftPM (bypassing Xcode's own resolver)...
Already up to date.
```

### `--dry-run`

Reports what would change without writing anything. Exit code `1` means
an update is available; `0` means already current. Useful to check
status without side effects, or as a CI gate:

```
~/code/PackageJam/.build/release/packagejam --dry-run ~/code/MyApp/MyApp.xcodeproj
```

## 3. The actual workflow this replaces

The situation that motivated this tool: a shared SwiftPM package
(`SomePackage`, used by several app projects) that gets a
new version tag pushed periodically. Before PackageJam, picking that new
tag up in a consumer required opening Xcode and manually clicking
**File → Packages → Update to Latest Package Versions** — once per
consumer, every single time, because no command-line invocation worked.

The replacement workflow, after tagging and pushing a new version of a
dependency like `SomePackage`:

1. Build (or confirm already built) the PackageJam release binary — §1.
2. Run it against each consumer's `.xcodeproj`.
3. Confirm the reported change matches what was expected (the version you
   just tagged).
4. Build the consumer project (e.g. via the `BuildProject` MCP tool in an
   Xcode-hosted session) to confirm it actually compiles against the new
   pin — the file being correct and the project building are two
   different claims, verify both.

No Xcode GUI interaction is required anywhere in this sequence.

## 4. Interpreting failures

Every failure path in this tool produces a specific, actionable message
(see `PackageJamError.description` in the source) rather than a bare
stack trace. What each one means and what to do:

- **`No .xcodeproj found in the current directory.`** — you're not `cd`'d
  into the right place, or the project's `.xcodeproj` has an unexpected
  name/location. Pass the path explicitly.
- **`Multiple .xcodeproj found (...)`** — ambiguous auto-discovery; pass
  the path explicitly.
- **`Neither project.xcproj nor project.pbxproj found inside ...`** — the
  path given isn't actually a valid `.xcodeproj` bundle.
- **`Couldn't parse ... — is plutil available, and is this a valid Xcode
  project?`** — the classic-format parse path failed; `plutil` is a
  standard macOS tool, so this usually means a genuinely malformed
  `project.pbxproj`.
- **`Found a package dependency with a version requirement PackageJam
  doesn't recognize yet (...)`** — you've hit one of the *inferred*
  (not yet individually confirmed) JSON field names documented in
  DESIGN.md §3.2. The error message includes the actual dictionary that
  failed to parse — that's exactly what's needed to fix
  `ProjectFileReader.parseJSONRequirement` or
  `parsePbxprojRequirement`. Fix the parser, add a test fixture using the
  real observed shape, done — don't guess a second time, use the exact
  string from the error.
- **`swift package resolve failed:\n<output>`** — the underlying resolve
  itself failed: a bad tag, an unreachable URL, a genuine SwiftPM
  manifest conflict. The `<output>` is `swift package resolve`'s own
  stderr/stdout, verbatim — read it, it's the same message you'd get
  running the command by hand.

## 5. Scope of pre-authorization

Per the standing project instructions, destructive or shared-state
actions (like `git commit`/`git push`) need explicit confirmation each
time, even when a similar action was approved before. **Running
PackageJam and letting it write a project's `Package.resolved` is
explicitly exempted from that** — it's a local, reversible,
single-file edit (§4 of DESIGN.md) that reproduces exactly what clicking
Xcode's own "Update to Latest Package Versions" button would have
produced. There is no meaningful difference in blast radius between "the
user clicks a GUI button" and "this tool performs the equivalent write,"
so treat the write itself as pre-authorized: don't ask before running
`packagejam` against a project, and don't ask before letting it overwrite
`Package.resolved`.

**What's still outside that authorization:** committing that changed
`Package.resolved` to git, and especially pushing it. Those remain
ordinary git operations subject to the usual rule — confirm with the user
first, unless a given conversation has already granted broader standing
permission for that specific repo. The distinction is deliberate: writing
a corrected dependency pin to disk is invisible until it's committed;
committing and pushing makes it visible to everyone else who pulls the
repo, which is exactly the kind of action the standing git-safety
guidance means to gate.

## 6. Keeping this doc itself trustworthy

If the source changes in a way that would make a claim in this file or
DESIGN.md wrong — a new project format field gets confirmed, a
limitation gets lifted, the temp-target name changes — update the
relevant doc in the same commit. A memory file elsewhere (e.g. a
consuming project's auto-memory) may point at this tool and summarize it,
but this repo's own docs are the source of truth; if the two ever
disagree, trust what's here and fix the memory pointer, not the other way
around.
