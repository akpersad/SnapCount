# Meta Display Glasses

Research and prototyping space for building on Meta Ray-Ban Display glasses.

Hardware on hand: Meta Ray-Ban Display + Meta Neural Band. Meta developer account exists.

## Status

| Item | State |
|---|---|
| Meta developer account | Done |
| Developer Mode in Meta AI app | Enabled (2026-09-03) |
| Wearables Developer Center org | Not created yet |
| Wearables Developer Center project | Not created yet (intentionally deferred) |
| Chosen build path | Device Access Toolkit (native) |
| App idea | DECIDED: on-device face-count app, see `snapcount/` |

## Direction

Going the **native Device Access Toolkit** route rather than Web Apps. Reason: more control over
actual hardware. It is the only path with camera and microphone access, and it supports the whole
glasses lineup instead of Display only.

Web Apps research is retained in `research/web-apps.md` as a fallback and for comparison.

## Contents

- `research/build-paths.md` - the two SDK paths, side by side comparison
- `research/device-access-toolkit.md` - native path: capabilities, config keys, registration model
- `research/web-apps.md` - web path: 600x600 constraints, d-pad input, available APIs
- `research/setup-developer-mode.md` - version requirements, Developer Mode steps, troubleshooting
- `research/constraints-and-limits.md` - hard blockers, preview-status caveats, gotchas
- `research/sources.md` - every URL consulted
- `ideas.md` - app idea brainstorm (placeholder, to be filled in a later session)

## Open questions

Several were resolved on 2026-09-22. See `snapcount/research/dat-api-findings.md`.

1. Text input: still unresolved, but no longer blocking. `snapcount` needs no text entry.
2. ~~Display UI component set~~ **RESOLVED**: flexbox system with `FlexBox`, `Text`, `Image`,
   `Button`, `ButtonGroup`, `Icon`, `VideoPlayer`. Note `Image` loads from URL only.
3. ~~Neural Band gesture events on native~~ **PARTIALLY RESOLVED**: interaction events do reach
   native apps. `Button` has tap handlers. Whether raw swipe/pinch is exposed is still unknown.
4. ~~Full iOS permission enum~~ **RESOLVED**: `Permission` has exactly one case, `.camera`.
5. ~~Camera stream data path~~ **RESOLVED**: local Wi-Fi via Bonjour, or BLE without streaming.
   Image data does not transit Meta's cloud. But SDK telemetry is on by default and must be
   disabled with `OptOut = true`.
