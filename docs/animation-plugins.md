# Animation plugins

Install a JSON plugin with **Appearance → Install animation…**, choose it for Entry
or Dismissal, adjust its generated controls, then Apply. Files live in
`~/Library/Application Support/Dock Peek/Animations/`. Installing a plugin does
not activate unsaved settings. A plugin can support entry, dismissal, or both.
The [Fade and lift example](examples/fade.json) demonstrates all three setting types.

Slide and Tumble are native built-in plugins registered through the same
`AnimationPlugin` interface. Slide supports both stages; Tumble supports entry.
None is an immediate host transition. Existing animation selections and durations
continue to load. Settings are retained independently per plugin and stage.
Returning from a visible Dock or active application still uses Slide.

## Contract

The host supplies `AnimationContext`: stage, final panel frame, screen frame,
current pose, raw unread indicator, optional numeric unread count, and an unread
boolean. Geometry uses macOS global screen coordinates, in points, with Y upward.
`finalFrame` is the 128-point panel canvas; the icon itself is 54 points square
at canvas position (37, 37), with the unread badge at its upper-right corner.
Nonnumeric badges such as `4+` retain their label; their numeric count is unknown.

A plugin declares an ID, display name, supported stages, and typed settings.
Setting IDs are local to the plugin; each has a label and a default value:

| Kind | Value | Additional fields | Control |
| --- | --- | --- | --- |
| `number` | JSON number | `minimum`, `maximum` | Slider |
| `toggle` | JSON boolean | — | Toggle |
| `choice` | JSON string | Unique `choices` strings | Picker |

Every plugin must declare a numeric `duration` in seconds, with bounds greater
than zero and no greater than **15 seconds**. Invalid saved setting values use
that setting's declared default. Unknown setting keys are ignored. Unknown or
unsupported selected plugins hide peeks until a valid selection is saved.
Broken plugin files are reported in settings and do not disable other plugins.
Built-in IDs cannot be overridden. IDs contain only lowercase ASCII letters,
digits, periods, and hyphens, and cannot name filesystem paths.

## JSON keyframes (version 1)

Each keyframe has `time` (normalized 0–1), `curve` (`linear`, `easeOut`, or
`easeInOut`), and six scalar fields: `travel`, `x`, `y`, `angle`, `squash`, `opacity`.
The destination keyframe's curve controls interpolation into that keyframe.
The first time must be 0, the last 1, with strictly increasing times between.

A scalar is a number, or `{ "binding": "height", "multiplier": -0.25, "value": 0 }`.
The formula is `value + input * multiplier`; omitted value and multiplier are
0 and 1. Bindings are flat; they cannot call code or refer to other expressions.

| Binding | Input |
| --- | --- |
| `width`, `height` | Final panel dimensions in points |
| `unreadCount` | Numeric unread count, or 0 when unknown |
| `hasUnread` | 1 for an unread indicator, otherwise 0 |
| `direction` | -1 when the nearest screen edge is left, otherwise 1 |
| `entering` | 1 for entry, 0 for dismissal |
| `setting.ID` | Number, toggle as 0/1, or mapped choice |

A choice binding supplies a complete numeric map, for example
`{"binding":"setting.direction","choices":{"up":0,"down":8}}`.

`travel` interpolates the initial point toward the host's destination; `x` and
`y` add point offsets. Entry starts at the final frame origin, so offsets define
its arrival path. Dismissal starts from the current visible pose and travels below
the screen. `angle` adds radians to the initial rotation as it unwinds with travel.
`squash` stretches vertically and inversely horizontally. `opacity` ranges 0–1.
The host keeps ownership of the icon, badge rendering, input, and application launch.
Plugins animate the existing panel; they cannot replace its content.

## Lifecycle and bounds

The host captures the plugin, context, and resolved settings when a transition
starts. Settings changes and file reloads affect the next transition. Dismissal
interrupts entry from its current pose; showing again during dismissal starts from
that interrupted pose. Keyframe offsets can deliberately move it from that pose.
Repeated hide requests cannot restart or extend the deadline.

A monotonic clock ends each transition at its declared duration, with an absolute
15-second maximum. On completion or an invalid frame, entry settles at the exact
host target with normal rotation, squash, and opacity; dismissal hides the panel.
There are no plugin timers or callbacks left running. A suspended run loop finishes
on its next tick rather than restarting the timeline.

Limits: 64 external plugins, 64 KiB per file, 16 settings per plugin, 16 choices,
and 2–256 keyframes. Numbers and maps must be finite and bounded. Rendered poses
must stay within four panel widths of the screen, squash 0.1–4, opacity 0–1, and
rotation within 50 turns. Invalid manifests are rejected before registration.
Reloads are cached using file names, modification times, and sizes; in-flight
transitions retain their original plugin. Removing the directory clears the catalog.

External plugins are declarative data. A time limit cannot preempt arbitrary
in-process Swift code, so downloadable native bundles and scripts are not loaded.
Native contributors implement the trusted `AnimationPlugin` protocol and add their
plugin to `AnimationRegistry`; they must satisfy the same descriptor and pose
checks. Supporting executable third-party plugins would require a separately
supervised process and a different API.

## Research and design decision

[GSAP's plugin registration](https://gsap.com/docs/v3/Plugins/) informed the explicit
registry and stable identifiers. [Remotion compositions](https://www.remotion.dev/docs/composition)
show how duration, geometry, and a settings schema can accompany animation content.
[Rive data binding](https://rive.app/blog/getting-started-with-data-binding) informed
typed numeric, boolean, and choice inputs. The
[Web Animations keyframe API](https://developer.mozilla.org/en-US/docs/Web/API/KeyframeEffect)
informed bounded keyframes separated from the host timeline.

We compared native dynamic bundles, supervised script executables, and declarative
keyframes. Native bundles cannot enforce a deadline against blocking code and
complicate signing. Separate executables can be terminated, but require IPC,
resource limits, and packaging for every plugin. Declarative keyframes provide
installable animations, generated settings controls, and enforceable work bounds
without a third-party interpreter. Built-ins retain their existing analytic motion
behind the common interface rather than approximating Tumble with sampled frames.

## Verification

Run `make format`, `make check`, `make sanitize`, and `make integration`.
`AnimationPluginTests` exercises typed settings, bindings, schema and resource
bounds, interpolation, legacy configuration, clock deadlines, interruption,
invalid poses, catalog caching, installation, and removal. Packaged integration
loads the example into an isolated runtime and checks rendering, timer shutdown,
dismissal, missing-plugin behavior, and restoration.
These fixtures do not establish physical Dock positioning or Accessibility grants.
