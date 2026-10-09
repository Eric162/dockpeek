# Dock Peek

Dock Peek shows a small part of an app's icon and badge at the bottom of the screen
while the macOS Dock is hidden. Choose which apps can peek without revealing the
whole Dock.

The settings app uses SwiftUI. A separate AppKit worker draws the peeks and keeps
running when settings is closed or quit.

## Features

- Select apps from the Dock or add any application with the native file picker.
- Configure the visible portion of each icon, defaulting to one third.
- Choose slide-up, tumble, or no entry animation. Tumble makes three shrinking
  hops along the screen edge while completing two spins.
- Click to open an app. Scroll down or right-click to dismiss its current badge.
- Slide back up after the native Dock hides, without replaying tumble.
- Test Dock Peek's own icon for ten seconds without changing saved settings.
- Register startup through the native **Start at login** control.

Dock Peek reads the badge displayed by the Dock. It does not count Notification
Center notifications or reproduce custom, dynamically drawn Dock artwork.

## Requirements

- macOS 14 or later.
- Swift 6.3 or later and Xcode or the Xcode Command Line Tools.
- Python 3 for app-bundle packaging.
- Accessibility permission for **Dock Tile Probe** to read Dock tiles.

The current UI and overlay were tested on macOS 26.5.2. Placement is currently
validated for a bottom Dock on one display. Side Docks, multiple displays, and
fullscreen behavior need further testing.

## Build and run

```sh
make bootstrap
./scripts/check.sh
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
ditto 'dist/Dock Peek.app' "$HOME/Applications/Dock Peek.app"
open "$HOME/Applications/Dock Peek.app"
```

The default build is release. Use `./scripts/build-app.sh debug` for a debug app.
`./build.sh` is a shortcut to the same packaging command. Build output is ignored
by Git.

The app is ad-hoc signed for local use. Set `CODE_SIGN_IDENTITY` when packaging
with your own signing identity. Distribution, notarization, and release publishing
are not configured.

When replacing a running installation, quit settings and stop **Dock Peek Worker**
in Activity Monitor before copying the new app. Your settings are stored outside
the app bundle and survive replacement.

### Accessibility access

After the first launch, request access from the installed probe:

```sh
open "$HOME/Library/Application Support/Dock Peek/.build/Dock Tile Probe.app" \
  --args --request-access
```

Enable **Dock Tile Probe** under **System Settings > Privacy & Security >
Accessibility**. This is separate from the top-level Accessibility settings.
Rebuilding or replacing the authorized probe can require a new grant. Dock Peek
preserves an existing runtime probe when it starts.

### Settings and startup

Select apps, adjust appearance and interactions, then click **Apply**.
**Test Dock Peek** temporarily shows a synthetic badge for Dock Peek itself, even
when the global enable switch is off. It expires after ten seconds and does not
change the saved app list.

**Start at login** registers the settings app with `SMAppService.mainApp`. A login
launch starts the independent worker and exits settings. If macOS requires
approval, settings provides a link to Login Items. This local build does not
register its nested helper directly because that failed macOS launch-constraint
validation during development.

Settings, logs, the authorized probe, and temporary test requests live in:

```text
~/Library/Application Support/Dock Peek/
```

Examples of the JSON settings are in [Examples](Examples). Missing fields receive
default values. Invalid settings hide the overlays until a valid file is saved.

## Development

Open `Package.swift` in Xcode, or use Swift Package Manager:

```sh
make bootstrap
swift build
./scripts/test.sh
make format
make check
make app
```

The test script also supports Command Line Tools installations by resolving the
bundled Swift Testing framework and macro plugin. With full Xcode selected,
`swift test --disable-xctest` works directly.

Use the packaged app for UI testing. Running the bare settings executable with
`swift run` does not provide the nested worker and probe bundles or the installed
app identity needed for login registration.

```text
Sources/
  DockPeekCore/      Configuration, animation math, test requests, Dock parsing
  DockPeekSettings/  SwiftUI settings and background/login lifecycle
  DockPeekWorker/    AppKit panels, interactions, and badge monitoring
  DockTileProbe/     Accessibility probe
Tests/
  DockPeekTests/     Swift Testing coverage for shared behavior and settings persistence
Experiments/        Original bounce filter and disposable AppKit fixtures
scripts/            Checks, formatting, and signed app packaging
Examples/           Sample configuration files
docs/               Archived investigation and prototype evidence
```

Checks enforce strict formatting, semantic lint, Swift 6 concurrency checking,
and debug/release builds with warnings treated as errors. Core line coverage must
remain at 100%; compiler-based analysis checks unused imports. Git hooks and CI
enforce Conventional Commits. CI also runs address and thread sanitizer tests.
See [Contributing](CONTRIBUTING.md) for tool versions and commands.
Tests cover configuration validation, peek geometry, traveling tumbles, badge
parsing, Dock-return animation, temporary tests, and settings persistence.
GitHub Actions runs the same checks and verifies app packaging on macOS.

The worker currently launches a short-lived Accessibility probe once per second.
A future version can move the Accessibility reader into the worker to avoid this
process overhead. Logs and snapshots currently have no automatic retention policy.
An actual logout/login cycle has not yet been tested; the login-start path and
worker survival after settings quits have been tested locally.

## Earlier bounce experiments

The original native attention-state cancellation experiment remains in
[Experiments/BounceFilter](Experiments/BounceFilter). It uses private LaunchServices
APIs and is not part of the installed app. Dock Peek mirrors badges; it does not
filter native attention bouncing.

The investigation is preserved in [docs/dock-bounce-research.md](docs/dock-bounce-research.md)
and [docs/prototype-notes.md](docs/prototype-notes.md). Those documents describe the
earlier scratch layout and test runs. Generated binaries, snapshots, screenshots,
and logs are preserved locally under `Artifacts/Prototype`, which is ignored by Git.

## License

A license has not been selected yet.
