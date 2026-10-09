---
name: dockpeek-swift
description: Implement and verify DockPeek Swift changes, or maintain its compiler, lint, coverage, and CI gates.
---

# DockPeek Swift development

Read `Package.swift`, `Makefile`, and the relevant target before editing. Keep shared
configuration, geometry, and snapshot parsing in `DockPeekCore`; keep UI and
process lifecycle in the executable targets.

Swift 6 mode enforces concurrency checking. Keep AppKit and SwiftUI state on the
main actor. Timer callbacks currently enter through `MainActor.assumeIsolated`
because those timers run on the main run loop. Preserve that invariant when
changing scheduling. Investigate isolation errors before adding concurrency
escape annotations.

Use throwing operations or optional binding for fallible I/O and parsing. Invalid
saved configuration hides peeks until a valid save. Preserve that behavior. Test
changed core behavior with Swift Testing, including malformed and boundary input.

Run the checks required by `AGENTS.md`. Use `scripts/test.sh` rather than bare
`swift test` on Command Line Tools installations; it resolves Testing.framework
and the macro plugin. `make analyze` needs a fresh verbose build, including test
compiler invocations. Preserve its dedicated scratch directory and skip detection.

The formatter owns layout; SwiftLint owns semantic and complexity checks. When
updating tools, verify upstream versions and archive checksums, update bootstrap
and version verification together, and select matching Xcode in CI. Fix findings
before changing rule policy; justify any narrow exception next to its declaration.

For manual UI testing, use the packaged app with its nested worker and authorized
probe. Unit tests do not establish live Dock behavior or login registration. State
which manual paths were actually exercised. Avoid launching permission prompts or
changing the user's installation as part of automatic checks.
