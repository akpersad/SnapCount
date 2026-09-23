# DAT 0.9 API Findings

Researched 2026-09-22. Resolves several open questions carried from `../../ideas.md`.

## RESOLVED: the camera data path is local

This was the blocking question for the whole privacy model. Answer: **image data never
goes to Meta's cloud.**

- High-bandwidth camera streaming runs over **local network Wi-Fi**, discovered via Bonjour.
  Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_bonjour._tcp`).
- If the user denies Local Network access, the integration **continues over Bluetooth LE but
  loses streaming**. So Local Network permission is effectively required for camera work.
- Frames and photos are delivered straight into the app process via publishers. Meta's docs
  state developers "can process data locally or via cloud/edge platforms" - the cloud is an
  option the developer chooses, not a mandatory hop.

### BUT: telemetry is on by default

Separate from image data, and it must be turned off explicitly.

> "Meta may collect information about how users' Meta devices communicate with your app."

- Analytics: opt out with `MWDAT > Analytics > OptOut = true`
- Crash reporting: **enabled by default**, opt out with `MWDAT > CrashReporting > OptOut = true`
- Both are nested dictionaries. A bare `OptOut` under `MWDAT` is ignored (corrected
  2026-09-23 from the SDK README; earlier notes had it flat).

This is connection metadata, not image content. Turning both off is non-negotiable for this
project. See `../docs/privacy-architecture.md`.

## RESOLVED: the display component set

Richer than the earlier research suggested. It is a flexbox layout system.

| Component | Notes |
|---|---|
| `FlexBox` | Container. Row/column, spacing, alignment, wrapping. |
| `Text` | Styled. Heading / body / meta presets via `TextStyle`. |
| `Image` | **Loads from URL** - see the gotcha below |
| `Button` | Label, icon, style variants. Has tap handlers. |
| `ButtonGroup` | With `ButtonGroupAlignment` |
| `Icon` | Predefined set, via `IconName` / `IconStyle` |
| `VideoPlayer` | MP4 from URL |

Supporting enums: `Alignment`, `Background`, `CornerRadius`, `Direction`, `TextColor`,
`TextStyle`, `ImageSize`, `EdgeInsets`, `Edge`.

### Gotchas

1. **No partial updates.** Every display change re-sends the entire view via `send()`.
   Design the HUD as one small view that is cheap to retransmit.
2. **`Image` loads from a URL.** There is no "send me these bytes" path documented. Putting a
   face thumbnail on the glasses would mean running a local HTTP server on the phone.
   **Decision: the glasses HUD is text and icons only.** Avoids the problem entirely and
   keeps the design glanceable, which is what the display wants anyway.
3. Display lifecycle is `stopped -> starting -> started -> stopping` (`DisplayState`).

## RESOLVED: the permission enum

`Permission` has exactly **one** case in 0.9:

- `.camera` - "Permission to access camera functionality on the connected wearable device."

Notable: no microphone permission, and display needs no permission. Earlier notes assumed
mic was available on the native path. At 0.9 it is not gated by a permission, which suggests
it may not be exposed at all. Irrelevant for this project but worth correcting.

## Photo capture API

Capture is **not** independent of streaming. You add a camera to the session, get a `Stream`,
and capture from it.

```swift
import MWDATCore
import MWDATCamera

let config = StreamConfiguration(
    videoCodec: .raw,
    resolution: .low,
    frameRate: 24)
guard let camera = try session.addCamera(config: config) else { return }

_ = stream.photoDataPublisher.listen { photoData in
    let data = photoData.data   // raw bytes, straight into our process
    // -> hand to the recognition pipeline
}

stream.capturePhoto(format: .jpeg)
```

Streaming frames, if we want a preview:

```swift
let frameToken = stream.videoFramePublisher.listen { frame in
    guard let image = frame.makeUIImage() else { return }
}
stream.start()
```

Quality ladder is automatic under bandwidth pressure: resolution degrades first
(high -> medium -> low), then frame rate, never below 15 FPS.

**Implication for battery:** if the stream must be running to capture a photo, an all-day
"capture whenever" mode is expensive. Needs measurement on-device. Possible mitigation is
starting the stream on demand and accepting the startup latency.

## PARTIALLY RESOLVED: input events

Docs say users "control display integrations using captouch gestures and EMG gestures on the
Meta Neural Band," and `Button` has tap handlers. So interaction events do reach the native
app, contradicting the earlier guess that gestures were Web Apps only.

Still unverified: whether raw swipe/pinch events are exposed, or only button taps. For this
project button taps are sufficient.

## CORRECTION (2026-09-22, later): earlier Info.plist notes were wrong

`AGENTS.md` in the SDK repo contradicts the docs site on two keys, and adds one that was
missing entirely. See `../docs/setup-walkthrough.md` for the corrected table.

- Background mode is `bluetooth-peripheral` + `external-accessory`, **not** `bluetooth-central`
- `UISupportedExternalAccessoryProtocols` must include `com.meta.ar.wearable` - was missing
- `MetaAppID` can be **`0`** in developer mode, so a Developer Center project may be optional
- Module list also includes `MWDATDisplay` and `MWDATMockDevice`
- Meta hosts a public docs MCP at `https://mcp.developer.meta.com/wearables`, no auth

## Full Info.plist key list (SUPERSEDED - see setup-walkthrough.md)

Inside an `MWDAT` dictionary:
- `AppLinkURLScheme`
- `MetaAppID`
- `ClientToken`
- `TeamID`

Top level:
- `CFBundleURLTypes` - matching the AppLinkURLScheme
- ~~`UIBackgroundModes` - `bluetooth-central`~~ **WRONG.** It is `bluetooth-peripheral` plus
  `external-accessory`. See `../docs/info-plist.md`.
- `NSBluetoothAlwaysUsageDescription`
- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` - `_bonjour._tcp`
- `NSCameraUsageDescription` - for MockDevice feeds

## SPM

`https://github.com/facebook/meta-wearables-dat-ios` at tag `0.9.0` (no `v`).
Products (confirmed from `Package.swift`): `MWDATCore`, `MWDATCamera`, `MWDATDisplay`,
`MWDATMockDevice`, `MWDATMockDeviceTestClient`. Binary xcframeworks with device and simulator
slices.

## Sources

- https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.9
- https://wearables.developer.meta.com/docs/develop/dat/display-overview/
- https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/
- https://wearables.developer.meta.com/docs/reference/ios_swift/dat/latest/mwdatcore_permission
- https://github.com/facebook/meta-wearables-dat-ios
