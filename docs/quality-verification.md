# Quality and performance verification

Requested work: implement worker-state tests, bounded asynchronous probing, typed
animation states, lifecycle failure tests, packaged integration tests, then run a
CPU/memory pass and create an agent verification skill.

The worker now renders decisions from `WorkerState`. `PresentationMotion` owns
animation transitions with an injected monotonic clock. Configuration enums retain
the existing JSON strings. Unknown strings fail decoding and hide peeks.

The runtime owns each probe process directly, bounds its execution, escalates an
uncooperative child from SIGTERM to SIGKILL, and waits for termination before
completing cancellation. Late callbacks are scoped to their original request.
Probe failures hide peeks until a successful read. Worker lock descriptors close
on exec and explicitly unlock on release, including concurrent child launches.

Packaged integration initially caught a shutdown stall in AppKit's nested
terminateLater event loop. Shutdown now cancels and drains the probe before
retrying termination. The same integration command then passed all 16 assertions.

## Evidence

- 29 Swift tests passed, including parameterized state and animation cases.
- Core executable-line coverage is 100%, including worker decisions and motion.
- Packaged integration covers settings quit, simulated login start, stale PID,
  duplicate worker, native right-click/scroll callbacks, badge changes, Dock
  return, failed/hung probes, configuration recovery, and drained shutdown.
- Fixtures use marked temporary roots. They never alter the installed app's
  settings, Accessibility grants, or Login Items.
- Actual system and physical interaction checks are listed in
  [Manual verification](manual-verification.md); those remain separate evidence.

## Performance method

Release bundles on macOS 26.5.2, three-second warmup followed by twelve seconds of
sampling per scenario. `/usr/bin/time -l` includes startup and drained shutdown;
`ps` samples resident memory after warmup. Synthetic probe data keeps scenarios
repeatable. These results do not measure real Accessibility traversal or native
Dock rendering overhead.

The comparison baseline is the completed functional refactor before the
performance changes, rather than the previous repository commit. An earlier
original-worker idle measurement is retained locally for context.

| Scenario | Baseline CPU | Baseline RSS range | Baseline animation callbacks |
| --- | --- | --- | --- |
| Disabled/idle | 0.769% | 32,816–33,056 KiB | 924 |
| Stable visible badge | 8.349% | 43,920–44,000 KiB | 920 |
| Changing badge | 8.896% | 44,080–44,384 KiB | 912 |

| Scenario | Optimized CPU | Optimized RSS range | Optimized animation callbacks |
| --- | --- | --- | --- |
| Disabled/idle | 0.632% | 27,104–33,072 KiB | 0 |
| Stable visible badge | 2.859% | 40,160–43,760 KiB | 1 |
| Changing badge | 2.685% | 38,976–44,192 KiB | 1 |

Settled and changing-badge CPU decreased by about 66% and 70% against the stated
baseline. Timers now run only during transitions, icons reload only when their
path changes, and snapshot regular expressions are compiled once. Single-badge
peak RSS did not materially decrease.

Five repeated cycles of 32 simultaneous peeks released every retained renderer,
icon, and animation timer. Hidden-state RSS rose to 162,704 KiB after the first
cycle and plateaued at 167,392 KiB after the fifth (4,688 KiB growth). This verifies
bounded growth for this fixture, not universal memory bounds or zero allocation.
The retention gate allows at most 32 MiB growth after the first cycle.

`sample` showed the settled worker predominantly waiting in the event loop.
`leaks` reported approximately 14 KiB of Foundation/XPC cycles involving
`LNDaemonApplicationInterface` in idle, single-badge, and repeated-panel runs.
No app-owned renderer root appeared in those reports. Framework attribution is
an inference from their matching roots; the finding remains unresolved and these
runs must not be described as leak-free.

Raw local evidence is ignored under `Artifacts/Performance/before`, `after`, and
`inspection`. `scripts/performance.py` and `scripts/memory_retention.py` reproduce
the measurements on another host. CI enforces broad CPU/RSS budgets and timer/icon
invariants; actual Dock traversal and physical interactions need manual evidence.
