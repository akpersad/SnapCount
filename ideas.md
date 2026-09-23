# App Ideas

Placeholder. Brainstorm deferred to a later session by request.

## Design constraints any idea has to survive

Copied here so ideas get filtered against reality rather than wishful thinking.

1. **Input budget is a d-pad plus two buttons.** Four swipes, index pinch = enter, middle pinch =
   cancel. No custom gestures.
2. **Assume no text entry.** Contested in the docs, unverified on device.
3. **Peripheral vision of one eye, additive display, black is transparent.** Glanceable beats
   comprehensive. If it needs reading, it is probably wrong.
4. **No real users.** Publishing is closed. Optimize for learning or for being early on a pattern.
5. **Display work needs the physical glasses.** MockDeviceKit does not simulate the display.

## Shapes that fit the device

From the initial research pass, not yet evaluated or chosen.

- **Timers, counters, steppers.** Recipe steps, workout sets, medication timing. Discrete state,
  no text entry, no camera.
- **Heads-up readouts** driven by phone GPS or glasses orientation: compass bearing, pace, distance
  to a waypoint, transit countdown.
- **A single "what's next" card** pulled from an API already under our control.
- **List navigators.** Four-way focus over a short list is the genuinely native interaction here.
- **Simple games.** Snake is Meta's own shipped example because a d-pad plus a small grid is exactly
  what the input model supports.

## What the native path unlocks that Web Apps cannot

Worth biasing ideas toward these, since they are the reason the native path was chosen.

- Camera stream and photo capture
- Microphone input and audio output
- The rest of the glasses lineup, not just Display

Ideas that use none of the above are arguably better built as Web Apps for the faster iteration loop.

## Open questions to resolve before or during brainstorm

1. Is text input actually available on device? (see `research/constraints-and-limits.md`)
2. What is the real display UI component set on the native path? Reported as text, images, lists,
   buttons, video playback. Needs verification against the 0.9 API reference.
3. Does the native path receive Neural Band gesture events, or is that Web Apps only? Not documented
   either way in what has been read so far.
4. What is the full permission enum list on iOS?
5. Any latency or frame rate ceiling on the camera stream that would rule out real-time processing?
