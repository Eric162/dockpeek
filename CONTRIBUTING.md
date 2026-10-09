# Contributing

Use Swift 6.3 on macOS 14 or later. Open `Package.swift` in Xcode or use the CLI.

Follow [the Swift style guide](docs/swift-style.md), which adopts the official
Swift API guidelines and Google's conventions with documented project exceptions.

Before submitting changes, run:

```sh
make bootstrap
make format
make verify
make performance
```

Keep AppKit and SwiftUI lifecycle code in their respective executable targets.
Shared configuration, geometry, parsing, and worker decisions belong in
`DockPeekCore`; bounded subprocess execution belongs in `DockPeekRuntime`. Add tests
when changing behavior and include manual evidence for Dock interactions that
cannot be exercised by the unit tests.

Use conventional commit messages, such as `fix: preserve dismissal for unchanged badges`.
Do not commit generated app bundles, logs, Accessibility snapshots, or local settings.

`make bootstrap` downloads checksum-verified SwiftLint 0.65.1 into `.tools` and
installs repository-local Git hooks. The formatter must be swift-format 6.3.0,
provided by Xcode 26.5 or matching Command Line Tools. No global Git settings or
Homebrew packages are changed.

`make check` runs strict formatting and semantic lint, debug and release builds
with warnings as errors, Swift Testing with a 100% core line coverage gate, and
SwiftLint compiler-based unused-import analysis. Reports live in `.build/reports`.
`make sanitize` runs the tests separately under AddressSanitizer and ThreadSanitizer.
`make integration` checks the signed packaged app with isolated synthetic
fixtures; `make performance` checks resource budgets and timer/icon invariants.
Physical Dock rendering and real login behavior use
[the manual checklist](docs/manual-verification.md). Experiments receive the same compiler and lint checks as app code.

The pre-commit hook runs `make check`. Stage or stash all changes before a
commit so the checked working tree matches the index. The commit-msg hook requires
`type(scope): description` or `type: description`, with an optional `!` and a
maximum subject length of 72 characters. Supported types are defined in
`scripts/check_commits.py`. The pre-push hook checks outgoing subjects and reruns
`make check`. CI also checks commit subjects and runs sanitizers and signed app
packaging. Hooks can be bypassed by Git; server-side required checks need GitHub
branch rules configured separately.

Project agent guidance is in `AGENTS.md`, `.agents/skills/dockpeek-swift`, and
[the verification skill](.agents/skills/verify-dockpeek/SKILL.md).
