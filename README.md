# Meta Display Glasses

Research and prototyping space for building on Meta Ray-Ban Display glasses.

> **Start at [`WORKPLAN.md`](WORKPLAN.md).** That is the single source of truth for status,
> decisions, and next steps. The files below are background research, some of it superseded.

Hardware on hand: Meta Ray-Ban Display + Meta Neural Band. Meta developer account exists.

## Status

| Item | State |
|---|---|
| Meta developer account | Done |
| Developer Mode in Meta AI app | Enabled (2026-09-03) |
| Wearables Developer Center org | Done |
| Wearables Developer Center project | Done. Configured, camera permission on |
| Chosen build path | Device Access Toolkit (native) |
| App idea | DECIDED: on-device face-count app, see `snapcount/` |

## Direction

Going the **native Device Access Toolkit** route rather than Web Apps. Reason: more control over
actual hardware. It is the only path with camera access, and it supports the whole glasses
lineup instead of Display only.

**Correction (2026-09-22):** earlier notes here claimed microphone access too. That is now
contested. The 0.9 `Permission` enum has exactly one case, `.camera`. See the microphone note
in `research/device-access-toolkit.md`. It does not affect `snapcount`, which needs no audio.

Web Apps research is retained in `research/web-apps.md` as a fallback and for comparison.

## Contents

- **`WORKPLAN.md` - start here. Status, decisions, phases, open questions.**
- **`snapcount/` - the actual project.** Recognition core, docs, and setup.
- `research/build-paths.md` - the two SDK paths, side by side comparison
- `research/device-access-toolkit.md` - native path: capabilities, config keys, registration model
- `research/web-apps.md` - web path: 600x600 constraints, d-pad input, available APIs
- `research/setup-developer-mode.md` - version requirements, Developer Mode steps, troubleshooting
- `research/constraints-and-limits.md` - hard blockers, preview-status caveats, gotchas
- `research/sources.md` - every URL consulted
- `ideas.md` - historical brainstorm. Superseded; the app idea is decided.

## Open questions

Several were resolved on 2026-09-22. See `snapcount/research/dat-api-findings.md`.

1. Text input: still unresolved, but no longer blocking. `snapcount` needs no text entry.
2. ~~Display UI component set~~ **RESOLVED**: flexbox system with `FlexBox`, `Text`, `Image`,
   `Button`, `ButtonGroup`, `Icon`, `VideoPlayer`. Note `Image` loads from URL only.
3. ~~Neural Band gesture events on native~~ **PARTIALLY RESOLVED**: interaction events do reach
   native apps. `Button` has tap handlers. Whether raw swipe/pinch is exposed is still unknown.
4. ~~Full iOS permission enum~~ **RESOLVED**: `Permission` has exactly one case, `.camera`.
5. ~~Camera stream data path~~ **RESOLVED**: local Wi-Fi via Bonjour, or BLE without streaming.
   Image data does not transit Meta's cloud. But SDK analytics and crash reporting are on by
   default and must each be disabled with a nested `OptOut` (see `snapcount/docs/info-plist.md`).
