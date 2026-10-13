---
name: verify-dockpeek
description: Verify DockPeek changes with compiler, lint, coverage, sanitizer, packaged lifecycle, and CPU or memory tools. Use for release verification and runtime regressions.
---

# Verify DockPeek

Run from the repository root on macOS. Read `AGENTS.md` and `Makefile` for required
checks. `make bootstrap` installs pinned tools and local hooks. Run `make format`
after Swift edits, then `make verify` for quality, sanitizers, and signed packaged
integration. Inspect exit status and reports before declaring success.

Use `scripts/test.sh` for targeted Swift Testing runs on Command Line Tools;
bare `swift test` may fail to find Testing.framework or its macro plugin.
`make analyze` rebuilds all products and tests in a fresh disposable scratch directory.
Retain its compiler-command completeness check; reports survive scratch cleanup. Coverage and analysis reports
are in `.build/reports`; core coverage must stay at 100%.

Packaged integration launches the actual settings app, worker, and bundled probe
under marked temporary roots. It checks lifecycle, native view callbacks, probe
failure and timeout recovery, and drained shutdown. Probe snapshots, Dock
visibility, and login startup are simulated. Use
[the manual checklist](../../../docs/manual-verification.md) for physical Dock,
Accessibility grants, displays, and actual logout/login; report unperformed paths.
Automatic checks leave the user's installed worker and Login Items untouched.

## Animation plugins

Read [the plugin contract](../../../docs/animation-plugins.md). Run
`./scripts/test.sh --filter AnimationPluginTests` for schema, typed settings,
bindings, installation, captured configuration, interrupted transitions, invalid
poses, and the 15-second monotonic deadline. Keep core coverage at 100%.

`make integration` installs the checked-in `docs/examples/fade.json` under an
isolated root and verifies entry, dismissal, stopped timers, removal, and recovery.
The example includes numeric, toggle, and choice settings. For its CPU/RSS and
stopped-timer budgets, run `python3 scripts/performance.py --seconds 12 --gate
--plugin docs/examples/fade.json --output Artifacts/Performance/animation-plugin`.
Process timing includes entry; RSS samples follow warmup. This is one entry per
worker, not sustained animation throughput. Use the packaged
settings window to check generated controls and importing a JSON file; integration
does not click the import dialog or establish physical Dock placement. Preserve
the installed probe and the user's settings when explicitly updating their app.

## CPU and memory

Build a fresh release bundle with `make app`, then use:

```sh
python3 scripts/performance.py --seconds 12 --gate --output Artifacts/Performance/current
python3 scripts/performance.py --seconds 3 --inspect --output Artifacts/Performance/inspection
python3 scripts/memory_retention.py
```

The first command measures idle, settled, and changing badges using `time -l`
and sampled RSS, and checks broad resource budgets, icon reuse, and stopped
animation timers. Compare equal durations and warmup on the same host. The second
collects `sample` stacks and `leaks` output; profiler overhead changes timing.
The retention command creates/removes 32 peeks five times, checks renderer counts
and bounded RSS growth, and writes `Artifacts/Performance/after/retention.json`.
All fixtures are synthetic; these numbers exclude real Accessibility traversal.

Read raw profiler findings even when the script succeeds. `leaks` findings are
recorded rather than silently accepted as leak-free. Compare idle findings with
repeated-panel results before attributing framework cycles to app ownership.
RSS can plateau above its initial value because framework caches retain pages.
[Recorded evidence](../../../docs/quality-verification.md) describes the current
baseline and known findings; rerun measurements for a changed build.

`sample`, `leaks`, `ps`, and `/usr/bin/time` work with Command Line Tools.
Check `xcrun xctrace version` before choosing Instruments automation: the CLI stub
can exist while full Xcode and xctrace are unavailable. Choose a working Xcode
with `DEVELOPER_DIR` if Instruments is needed.

Scripts clean up only their owned children. On a failed fixture, inspect its
captured PID and executable path before cleanup. Require the worker's
`STOPPED worker; probe drained` log for successful shutdown verification.
