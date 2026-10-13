# Test and size audit

Baseline: `bdc04ab`,43Swift tests in8suites,6Python tests,100%core line coverage.
Applied [OpenClaw's test-audit workflow](https://github.com/openclaw/openclaw/blob/main/.agents/skills/test-audit/SKILL.md)
with read-only owner inventories, consolidation plans, and independent preservation
review. The audit retains independent contracts rather than deleting to a quota.

| Owner | Retained proof | Retired or repaired |
| --- | --- | --- |
| Config/parser/geometry | Defaults, wire compatibility, malformed input, Unicode, badge clipping | Duplicate negatives/private regex tests; geometry now uses independent dimensions |
| Plugins/motion | Schema/resource caps, typed settings, migrations,15-second deadline, interrupted motion, unsafe poses | Repeated lifecycle setup, static inventory; scalar and curve expectations now literal |
| State/preview | Activation/Dock hiding, dismissal, badge changes/clears, other-app isolation, disappearance,10-second expiry | Shared tables and one preview serialization owner |
| Processes | Direct child and actual LaunchServices ownership, metadata compatibility, overlap, cancellation, timeout, reuse | Continuation/timer bookkeeping replaced with one owned run; PID-reaping and pre-cancel proof strengthened |
| Settings/login | Persisted selection, preserved config/probe, registration/approval/error handling | Unused prototype CLI modes; safe login fakes retained |
| Packaged QA/tools | Marked storage isolation, native callbacks, shutdown, CPU/RSS, multi-panel retention, gate rejection | Historical-log false positive, duplicate assertions; actual unmarked-root rejection added |

Deliberate mutations were caught at their intended assertions: lost scalar binding,
linearized easing, shifted badge geometry, and skipped child drain. Sources were
restored byte for byte. Independent review also caught lost profiling-worker logging;
the uncorrected packaged build failed on missing`overlay.log`, then logging was restored.

Unused bounce/prototype targets, icon-export/demo/config CLI modes, and their stale
docs are retired. Original source remains in Git history. No current feature,
quality gate, sanitizer, or distinct platform test was removed. A previously observed
intermittent LaunchServices reuse failure remains unproven; passing reruns are not
claimed as a repair. Physical Dock, UI import, and logout/login checks remain manual.

Count maintained files with `pnpx cloc --vcs=git`. Plain `pnpx cloc .` also counts
SwiftPM YAML plans, output maps, module metadata, coverage, and ignored prototypes.
Analysis/sanitizer caches are disposable; their reports survive cleanup. The pinned
formatter now stores only overrides, with exactly the same effective policy.
