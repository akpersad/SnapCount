# Web Apps (Not the chosen path, kept for reference)

Ray-Ban Display only. Standard HTML/CSS/JS on a public HTTPS URL, rendered on the glasses.

Toolkit repo: https://github.com/facebookincubator/meta-wearables-webapp
Notably ships a **Claude Code plugin** (also Codex, Cursor, GitHub Copilot) and a Snake example.

## Requirements

- Glasses software v125+
- Meta AI app v272+
- Developer Mode on
- Public HTTPS host (Vercel, Netlify, Replit all called out by name)

## Display constraints

- **600x600 fixed viewport. No scrolling.** `body { overflow: hidden; }` required.
- **Additive display**: black renders as transparent. Dark backgrounds with bright, high-contrast
  foregrounds is the design language.
- Typography floor: 16px body, 20-24px primary content.
- Small, sits in the peripheral vision of one eye. Glanceable and contextual wins; anything
  resembling a full app screen loses.

## Opt-in meta tags

```html
<meta name="description" content="...">
<meta name="mrbd-web-app-capable" content="yes">
```

## Input: d-pad only

Both the Neural Band and the temple captouch strip surface as **keyboard events**:

| Action | Key |
|---|---|
| Navigate | `ArrowUp` `ArrowDown` `ArrowLeft` `ArrowRight` |
| Select | `Enter` |
| Back | `Escape` |

No mouse, no touch, no continuous cursor. Every interactive element must be reachable by
directional focus and needs a visible `:focus` state. Convention is a `.focusable` class.

```javascript
const DPAD = {
  UP: 'ArrowUp', DOWN: 'ArrowDown',
  LEFT: 'ArrowLeft', RIGHT: 'ArrowRight',
  SELECT: 'Enter', BACK: 'Escape',
};

document.addEventListener('keydown', function(e) {
  switch (e.key) {
    case DPAD.UP: moveFocus('up'); break;
    case DPAD.DOWN: moveFocus('down'); break;
    case DPAD.SELECT:
      if (document.activeElement.classList.contains('focusable')) {
        document.activeElement.click();
      }
      break;
  }
  e.preventDefault();
});
```

## Available APIs

| API | Notes |
|---|---|
| `DeviceMotionEvent` | Accelerometer, gyroscope. Permission required via user gesture. |
| `DeviceOrientationEvent` | Heading, tilt, roll. Permission required. |
| `navigator.geolocation` | `getCurrentPosition()` / `watchPosition()`. Relayed from paired phone, 5-50m accuracy. |
| `localStorage` | 5 MB, persistent |
| `sessionStorage` | 5 MB, session-scoped |
| Web App Manifest | Icon discovery via `<link rel="manifest">` |

## Unavailable

Camera, microphone, notifications, offline support, standard back navigation, continuous cursor.
Audio APIs not mentioned either way.

Text input is **contested** — see `constraints-and-limits.md`.

## Simulator

Chrome extension. 600x600 frame, environment backgrounds, brightness / blur / auto-dim settings,
on-screen and physical d-pad input, viewport recording, QA checklist.
