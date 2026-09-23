# PackageJam

### Your dependency isn't stuck. Xcode's resolver just doesn't care that it is.

You tagged a new release. You ran `xcodebuild -resolvePackageDependencies`.
Nothing happened. You deleted `Package.resolved`. Still nothing. You
cleared every SwiftPM cache you could find. Still nothing. The only thing
that actually works is opening Xcode, clicking through a menu, and
watching a spinner — every single time, on every single machine, forever.

That's not a workflow. That's a tax. And it's been a known, filed,
reproducible bug for a while now — **FB16108036** — sitting in a queue
somewhere, apparently not costing anyone at Apple enough sleep to fix it.
Command-line resolution is table stakes for CI, for scripting, for any
build that isn't a human sitting in front of Xcode babysitting a menu.
A company that shipped the rest of the SwiftPM toolchain knows that. It
still hasn't been fixed.

So one developer and an AI assistant sat down and fixed it in an
afternoon. Not by hacking around it with guesses or scraped version
numbers — by doing the resolution *correctly*, the same way Xcode's own
GUI action does it internally, and writing the trustworthy result where
Xcode already expects to find it. If this was fixable in an afternoon by
two people with no access to Apple's source, "too hard to prioritize"
was never really the reason it stayed broken.

## What it actually does

Reads your project's declared package dependencies (either Xcode project
format), resolves them for real with `swift package resolve` — which,
unlike `xcodebuild`, has never once failed to find the latest tag
satisfying your version requirement — and writes the correct pins
straight into your project's `Package.resolved`. Your next build, from
Xcode or the command line, just uses it. No GUI required, no spinner, no
babysitting.

## Get it running

**PackageJam is a standalone CLI, not a package dependency** — don't add
it via Xcode's Add Package Dependencies, it has no library product to
link against. Clone it, build it, run the binary against your project.
Requires macOS 12 or later and a Swift 5.9+ toolchain (any recent Xcode):

```
git clone https://github.com/gvh/PackageJam.git
cd PackageJam
swift build -c release
.build/release/packagejam /path/to/YourApp.xcodeproj
```

```
Reading dependencies from YourApp.xcodeproj...
Resolving 1 package(s) directly with SwiftPM (bypassing Xcode's own resolver)...
  somepackage: 2.0.35 → 2.0.41

Wrote YourApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

`--dry-run` reports what would change without writing anything, and
exits non-zero when an update is available — wire it into CI and finally
get an actual, scriptable check for dependency drift, the thing Apple's
own tooling still can't do.

## What it supports

- Both Xcode project formats: classic `project.pbxproj` and the newer
  JSON-based `project.xcproj`.
- Every SwiftPM requirement kind: up-to-next-major, up-to-next-minor,
  exact version, version range, branch, and revision.
- Every other field in your `Package.resolved` (including `originHash`)
  untouched — only the pins are replaced.

## Known limitations

- One `.xcodeproj` at a time — a multi-project `.xcworkspace` needs to be
  pointed at each constituent project individually.
- Local (path-based) dependencies are skipped — there's nothing to
  resolve for those.

## Read more

- [DESIGN.md](DESIGN.md) — the full technical case: what was ruled out
  before concluding this is an Xcode bug, why the workaround is
  trustworthy rather than a heuristic, and every architectural decision
  in the source.
- [OPERATIONS.md](OPERATIONS.md) — a practical runbook, including exactly
  what's safe to automate and what isn't.

## Why free, why dual-licensed

MIT OR 0BSD, your choice. No copyleft, no attribution theater, no reason
for Apple, JetBrains, or anyone else shipping developer tools to avoid
just absorbing this outright. That's deliberate: the point isn't to own a
clever fix, it's to make the excuse for the bug staying unfixed a little
harder to find. If a two-person side project can ship a correct,
tested workaround for free, "it's complicated" stops being a satisfying
answer.

Licensed under either of [MIT](LICENSE-MIT) or [0BSD](LICENSE-0BSD), at
your option.

SPDX-License-Identifier: MIT OR 0BSD
