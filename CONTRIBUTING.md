# Contributing

Use Swift 6 on macOS 14 or later. Open `Package.swift` in Xcode or use the CLI.

Before submitting changes, run:

```sh
make format
make check
make app
```

Keep AppKit and SwiftUI lifecycle code in their respective executable targets.
Shared configuration, geometry, and parsing belong in `DockPeekCore`. Add tests
when changing behavior and include manual evidence for Dock interactions that
cannot be exercised by the unit tests.

Use conventional commit messages, such as `fix: preserve dismissal for unchanged badges`.
Do not commit generated app bundles, logs, Accessibility snapshots, or local settings.
