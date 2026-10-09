> Archived prototype notes. Paths and commands below refer to the original scratch layout. See the root README for current build instructions.

# Dock bounce filter experiment

A native Swift prototype can clear another application's Dock attention state
without activating it, changing global preferences, injecting code, or disabling
SIP. It uses private LaunchServices functions and checks each running Dock app
every 50 ms. This is cancellation after a request, so a brief initial bounce can
escape. It is not a guaranteed interceptor or a finished background service.

## Run

```sh
xcrun swiftc -warnings-as-errors DockBounceFilter.swift -o .build/dock-bounce-filter
# Observe for 60 seconds, changing nothing:
.build/dock-bounce-filter
# Cancel requests outside the allowlist for four hours:
.build/dock-bounce-filter --enforce --allow com.openai.codex --duration 14400
```

The installed `/Applications/ChatGPT.app` identifies itself as `com.openai.codex`
on this computer. Add other bundle IDs separated by commas. Stop with Ctrl-C.
The helper changes only transient attention state. Exiting needs no preference
restoration. Apps may submit requests again afterward. No launch agent is installed.

Attention bouncing must be enabled globally for allowed apps to bounce:

```sh
defaults write com.apple.dock no-bouncing -bool false
killall Dock
```

The Dock briefly restarts. To disable attention bouncing globally, use `true`
instead. Launch bouncing is separate and is controlled by “Animate opening
applications” in Desktop & Dock settings.

## Evidence and limits

Tested on this computer with macOS 26.5.2, SIP enabled:

- Apple's built-in `lsappinfo` changed a disposable AppKit app's `LSWantsAttention`
  flag from `true` to `false`, with an attention-change notification.
- The Swift helper cleared a critical attention request from a newly launched
  blocked fixture and left an allowlisted fixture's request at `true`.
- The helper also cleared an informational request from a blocked fixture.
- The helper compiles with warnings treated as errors and passes strict
  `swift-format` lint. The fixture also passes those checks.

These tests verify the state change, not frame-by-frame animation suppression.
Private APIs can change between OS releases. The helper currently filters regular
applications with bundle IDs. It does not filter launch animations or establish
coverage for every possible Dock animation path. Simultaneous apps, repeated
requests, real ChatGPT task completion, and long-running CPU cost still need testing.

The experiment was run only against the disposable fixture. No persistent filter
or global preference change was made by this investigation.

## Sources

- [Apple's AppKit attention request API](https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:))
- [Apple-authored lsappinfo manual, hosted mirror](https://keith.github.io/xcode-man-pages/lsappinfo.8.html), also available locally as `man lsappinfo`.
- [Apple's WebKit LaunchServices declarations](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/PAL/pal/spi/cocoa/LaunchServicesSPI.h)
- More context in [dock-bounce-research.md](dock-bounce-research.md).

## Icon, badge, and tile position probe

`DockTileProbe.swift` extracts an app's standard icon without Accessibility
permission, or inspects the Dock's Accessibility attributes with permission:

```sh
xcrun swiftc -warnings-as-errors DockTileProbe.swift -o .build/dock-tile-probe
.build/dock-tile-probe --icon-only /Applications/ChatGPT.app .build/chatgpt-icon.png
.build/dock-tile-probe
```

Icon extraction succeeded locally. The probe passes strict formatting lint and
compilation with warnings treated as errors. Dock inspection currently exits with
code 2 because this executable lacks Accessibility permission. A named app bundle
is now available at `.build/Dock Tile Probe.app`. To request permission and open
the relevant settings page, run:

```sh
open '.build/Dock Tile Probe.app' --args --request-access
```

Enable **Dock Tile Probe** under **Privacy & Security > Accessibility**, rather
than the top-level Accessibility settings. Launch through `open` after granting
access; direct execution from this agent's shell was denied despite the app grant,
while LaunchServices launch succeeded:

```sh
open -W -g --stdout "$PWD/.build/dock-attributes.txt" \
  --stderr "$PWD/.build/dock-probe-error.txt" '.build/Dock Tile Probe.app'
```

After the user enabled permission, the live probe read Calendar's badge as `10`
and Slack's as `1`. ChatGPT had no badge text. Its tile frame was
`x=1790.425049, y=1692, width=67, height=83` in Accessibility coordinates, with
Dock auto-hide enabled. The full snapshot is in `.build/dock-attributes.txt`.
This app is ad-hoc signed; a changed build may require another grant.

The useful tile attributes are `AXURL` for matching an application bundle,
`AXStatusLabel` for its displayed badge text, and `AXPosition`/`AXSize` for geometry.
Badge text can be a number, a dot, or another string; it is not a count of Notification
Center entries. The standard app icon does not necessarily reproduce a dynamically
drawn Dock image. With auto-hide, we must check whether geometry is offscreen,
unavailable, or retained before placing an overlay at the corresponding screen edge.

[BadgeBar's source](https://github.com/ahmetrende/BadgeBar/blob/main/Sources/BadgeBar/BadgeReader.swift)
demonstrates reading Dock badge text. Apple's
[position attribute documentation](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute)
defines the coordinate system. These provide a basis for an allowlisted icon-and-badge
overlay. The bottom-Dock placement test is recorded below.

## Visible peek prototype

`PeekOverlayPrototype.swift` draws a temporary clickable icon and badge at the
hidden Dock tile's horizontal position. It reads snapshots from the already-authorized probe app,
without rebuilding that app or requiring another Accessibility grant. It makes no
preference changes and exits automatically.

```sh
sh build.sh
# Show Slack's real badge above its hidden Dock position for 30 seconds:
.build/peek-overlay-prototype "$PWD" com.tinyspeck.slackmacgap 30
# Or watch ChatGPT; nothing appears until its Dock tile has a badge:
.build/peek-overlay-prototype "$PWD" com.openai.codex 30
```

A screenshot confirmed Slack's real icon and `1` badge above its native horizontal
tile position with the Dock hidden. Ghostty remained the foreground app. The cropped
evidence is `.build/peek-overlay-detail.png`. The disposable `BadgeFixture.swift`
changes badge text from `3` to `8` to no badge to exercise updates and disappearance.
The fixture test passed: exactly one `SHOW badge=3`, one `SHOW badge=8`, then
`HIDE`, with Slack excluded by that test's allowlist. Both temporary overlay
processes and the fixture exited. Strict Swift lint and compiler checks passed.
The short-lived probe occasionally caused `open -W` to report process-wait warnings;
the captured snapshots and lifecycle assertions still succeeded.

This experiment supports the current bottom Dock on one display. Side Docks,
multiple displays, fullscreen behavior, click-to-open behavior, and long-running
performance are not validated. It launches a short-lived probe every second; a
finished app should read Accessibility directly. It copies the standard bundle icon,
so dynamic Dock artwork is not reproduced. The original test runs were temporary. The installed service is described below.

## Peek and animation configuration

Edit `peek-config.json` before launching, or use the installed settings app. Missing fields receive defaults.

| Setting | Behavior |
| --- | --- |
| `peekFraction` | Visible fraction of the icon, default `0.3333333333333333`. The badge stays above it. |
| `entryAnimation` | `slide` from below the screen, `tumble` from the nearer left/right edge, or `none`. |
| `dismissAnimation` | `slide` down below the screen, or `none`. |
| `slideDuration`, `dismissDuration`, `tumbleDuration` | Animation durations in seconds. |
| `scrollDismisses`, `rightClickDismisses` | Default `true`. Scroll down or right-click to dismiss the current badge until it changes or clears. |
| `openAppOnClick` | Default `true`. A click opens the app and hides the peek. |

Tumble makes three shrinking parabolic hops along the bottom edge while completing
two full rotations, squashes at impact, and settles into the configured peek. The nearer side is chosen from the tile's
horizontal position. Landing has no sound effect.

```sh
# ChatGPT preview using an explicitly synthetic badge of 3:
.build/peek-overlay-prototype "$PWD" com.openai.codex 45 --demo
# Same preview with the tumble configuration:
.build/peek-overlay-prototype "$PWD" com.openai.codex 45 --demo \
  --config "$PWD/peek-tumble-config.json"
# Deterministic trajectory/peek checks; no UI appears:
.build/peek-overlay-prototype "$PWD" com.openai.codex 1 --self-test
```

`--test-click` dispatches an AppKit mouse-down event into the visible portion of
the panel after three seconds, exercising window hit-testing and the click handler.
This is an automated window-event test, not a physical mouse click. Slide and tumble
tests logged entry, settling, click, downward exit, and hidden state without
reappearing for the same badge. A screenshot of the one-third peek is
`.build/peek-third-visible.png`; a tumble-flight capture is
`.build/peek-tumble-flight.png`. The test badge is synthetic and does not modify
ChatGPT's actual Dock badge or notifications.

Additional live tests confirmed Slack entering from the left and ChatGPT from the
right. A disposable real badge fixture showed `3`, accepted dismissal, stayed
hidden for that badge, then reappeared for the new badge `8`. Moving toward the
native Dock can reveal it; this prototype hides its mirror while the native tile
is visible and shows it again when the Dock hides, unless the badge was dismissed.


## Installed Dock Peek and settings

`~/Applications/Dock Peek.app` is the minimal SwiftUI settings app. It configures
Dock apps plus any application chosen with **Add application**, enable/disable, visible fraction, entry and dismissal
animations and durations, and click behavior. **Apply** saves settings. **Test Dock Peek** temporarily enables a synthetic badge
for Dock Peek itself for ten seconds, including when the global switch is off,
without saving or changing selected apps. Selected apps appear first.

The installed runtime lives in `~/Library/Application Support/Dock Peek`, including
`peek-config.json` and the unchanged authorized probe. The overlay reloads valid
settings every second. Disabled or invalid settings hide the overlays.

The settings app bundles a separate `DockPeekWorker.app` background helper.
Closing or quitting settings leaves that worker running. **Start at login** uses
Apple's `SMAppService.mainApp` registration. A login launch starts the separate
worker and exits without keeping a settings window open. The native Login Items
approval state is shown in settings when approval is needed. The previous manually
installed LaunchAgent has been disabled and replaced by this registration. ChatGPT (`com.openai.codex`) and Grok Bot
(`com.anysphere.sand`) are selected, with a one-third peek, tumble entry, and
slide-down dismissal. Returning after a native Dock reveal always slides up instead
of replaying tumble. This service mirrors Dock badges; the experimental native
bounce filter is separate and is not running.

Run `sh build.sh` for strict Swift formatting checks, both compilations with
warnings treated as errors, and deterministic animation checks. Build outputs
stay in the scratch workspace; the installed app and runtime are copies.


The updated settings and overlay checks cover application selection and persistence,
click-open defaults, invalid-save protection, three traveling hops, and double spins.
AppKit event tests verified right-click and scroll-down dismissal and suppression of
an unchanged badge. `--test-dock-return` simulates Dock visibility through the same
update path and verifies tumble entry, hiding, then slide-up return. The probe is
launched with `open -n` so separate inspection runs can operate concurrently.


The build packages and signs `.build/Dock Peek.app`, including the unchanged probe.
The installed settings app and worker have separate bundle identities. Checks
cover an expiring self-test without changing saved settings, worker survival after
quitting settings, and the login-start path. An actual logout/login cycle has not
been performed. This locally signed build registers the main app for login and
starts its helper separately; directly registering the nested helper failed the
macOS launch constraint check.
