# Dock Peek

Dock Peek shows an app's icon and unread badge at the bottom of the screen while
the macOS Dock is hidden. Choose apps in settings; a separate worker keeps running
when settings closes. Peeks hide while their app is frontmost and return when you
switch away. Click to open; scroll down or right-click to dismiss the current badge.

Choose Slide, Tumble (three shrinking hops and two spins), or no animation.
[JSON animation plugins](docs/animation-plugins.md) provide generated settings
controls and bounded motion, with a 15-second limit. The host renders the icon/badge;
additional image, GIF, and emoji layers are not implemented.

Dock Peek reads the badge displayed by the Dock, not Notification Center counts or
custom Dock artwork. Bottom-Dock placement has been tested on macOS26.5.2 with one
display. Side Docks, multiple displays, fullscreen, and actual logout/login still
need [manual verification](docs/manual-verification.md).

## Build and install

Requires macOS14+, Swift6.3/Xcode26.5 or matching Command Line Tools, and Python3.

```sh
make bootstrap
make format
make verify
mkdir -p "$HOME/Applications"
ditto 'dist/Dock Peek.app' "$HOME/Applications/Dock Peek.app"
open "$HOME/Applications/Dock Peek.app"
```

Before replacing a running copy, quit settings and stop **Dock Peek Worker** in
Activity Monitor. Settings survive replacement. Packaging is ad-hoc signed;
`CODE_SIGN_IDENTITY` selects your signing identity. Notarization and distribution
are not configured. `make app` builds release; `./scripts/build-app.sh debug`
builds debug. Use the packaged app for UI/login testing, not `swift run`.

Grant Accessibility to the installed probe:

```sh
open "$HOME/Library/Application Support/Dock Peek/.build/Dock Tile Probe.app" \
  --args --request-access
```

Enable **Dock Tile Probe** in System Settings → Privacy & Security → Accessibility.
The authorized runtime probe is preserved during upgrades; replacing it can require
a new grant. The worker launches it as a macOS app once per second.

## Settings

Select apps, configure appearance/interactions, then **Apply**. **Test Dock Peek**
shows a synthetic badge for ten seconds without changing saved apps, even when the
enable switch is off. **Start at login** uses `SMAppService.mainApp`; approval may
be required in Login Items. Login launch starts the worker and exits settings.

Settings, logs, installed plugins, snapshots, and the probe live in
`~/Library/Application Support/Dock Peek/`. Missing config fields receive defaults;
invalid settings hide peeks until corrected. See [sample settings](Examples).
Logs/snapshots currently have no automatic retention policy.

## Development

[Contributing](CONTRIBUTING.md) describes the pinned quality tools and commands.
[Swift style](docs/swift-style.md) covers conventions. Target boundaries:

- `DockPeekCore`: configuration, plugins, geometry, parsing, worker decisions.
- `DockPeekRuntime`: owned subprocesses, file catalogs, paths, worker lock.
- `DockPeekSettings`: SwiftUI and background/login lifecycle.
- `DockPeekWorker`: AppKit panels, native callbacks, badge monitoring.
- `DockTileProbe`: Accessibility snapshot reader.

`make check` enforces formatting, semantic lint, compiler warnings as errors,
Swift6 concurrency,100%core line coverage, and compiler-based unused-import
analysis. Hooks/CI enforce Conventional Commits. `make verify` adds address/thread
sanitizers and signed packaged integration. Temporary analysis/sanitizer builds are
removed afterward; reports remain in `.build/reports`. Checks disable IDE indexing.
Use `pnpx cloc --vcs=git` to count maintained files; `pnpx cloc .` includes build
plans, module metadata, reports, and ignored local artifacts.

`make performance` checks synthetic CPU/RSS, stopped timers, and icon reuse.
See [verification evidence](docs/quality-verification.md),
[manual checks](docs/manual-verification.md), and the
[agent verification skill](.agents/skills/verify-dockpeek/SKILL.md).

Original bounce-filter/prototype experiments are retired from active builds.
Their source and investigation remain in
[Git history](https://github.com/Eric162/dockpeek/tree/bdc04ab/Experiments).
Dock Peek mirrors badges; it does not filter native attention bouncing.

A license has not been selected.
