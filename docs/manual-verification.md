# Manual verification

Use a packaged build in a separate test account for permission and login checks.
Record macOS version, commit, Dock orientation, display arrangement, and result.
`make integration` covers isolated synthetic snapshots and AppKit event dispatch;
it does not establish these physical or system behaviors.

| Scenario | Expected result |
| --- | --- |
| Accessibility denied or revoked | Worker stays responsive, hides peeks, and reports probe failure without prompting repeatedly. |
| Accessibility granted to runtime probe | Actual Dock badges match the peeks and update within the polling interval. |
| Physical click, right-click, and scroll | Click activates the selected app; enabled dismissal gestures suppress the current badge. |
| Dock reveal and hide | Peeks hide while native tiles are visible, then return with a slide. Dismissed badges stay dismissed. |
| Multiple displays, including negative coordinates | Each peek uses its app's display and remains on that display's visible edge. |
| Side Docks and fullscreen Spaces | Record actual placement; bottom-Dock geometry remains the supported contract until these cases are validated. |
| Quit and reopen settings | One worker remains running; reopening settings starts no duplicate. |
| Enable Start at login | Approval state is accurate; registration succeeds only after macOS accepts it. |
| Actual logout and login | Worker starts once; settings exits after preparing it; previously authorized probe remains usable. |
| Disable Start at login | Registration is removed while the current session's worker keeps working. |
| Replace an installed version | Preserve saved settings and the existing authorized runtime probe. |

Do not log out an active user's session, modify their Login Items, or replace their
installation merely to complete an automated verification run. Report these cases
as pending when the appropriate test environment is unavailable.
