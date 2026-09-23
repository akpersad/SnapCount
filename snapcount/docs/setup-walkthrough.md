# Setup Walkthrough

Verified against Meta's docs and the SDK repo's `AGENTS.md` on 2026-09-22.

> **Status: this is now history.** The Developer Center project was created and configured on
> 2026-09-22. A real `MetaAppID` and `ClientToken` are in `snapcount/Secrets.xcconfig`, the
> Universal link is `snapcount://`, and camera permission is toggled on.
>
> **For the values to actually use, see [`info-plist.md`](info-plist.md).** Everything below
> is kept only to explain how we got here and as a fallback if credentials need regenerating.

## Historical: you may not have needed a Developer Center project at all

`AGENTS.md` in `facebook/meta-wearables-dat-ios` states that **`MetaAppID` can be `0` in
developer mode**. A production ID from Wearables Developer Center is only needed for
distribution, and distribution is closed during the preview anyway.

This matters because the organization flow is heavier than it looks. Signing up redirects you
into creating a **Managed Meta Account (MMA)** organization at `work.meta.com` under your
company's official legal name. That is a business-account flow, and it is a lot of ceremony
for a personal weekend project.

**Recommended: try `MetaAppID = 0` first.** If registration succeeds, skip the Developer
Center entirely for now. Fall back to the full flow below only if it fails.

One caveat that argues for doing it anyway: the docs say camera permission must be
**declared on the Developer Center project**, and that "if no prompt appears, the permission is
probably not declared." Whether that applies when `MetaAppID` is `0` is untested. If the
camera permission prompt never fires, that is the first thing to suspect.

---

## Path A: developer mode only (try this first)

1. Confirm Developer Mode is on. Meta AI app > Settings > App Info > tap the version number
   five times > toggle **Developer Mode**.
2. Set `MetaAppID` to `0` in Info.plist.
3. Build to device, call `Wearables.configure()`, then `startRegistration()`.
4. Check Meta AI **Settings > App connections > Developer mode apps**. Your app should appear.
5. Request camera permission and confirm the prompt fires.

If step 4 or 5 fails, go to Path B.

---

## Path B: full Wearables Developer Center setup

### 1. Organization

- Go to https://wearables.developer.meta.com/ and sign up.
- You are redirected to MMA setup at `work.meta.com`.
- Use an official legal name for the organization.
- Meta's guidance is **one MMA organization per company**. For a personal project you are the
  admin and the only member.
- On first login to Developer Center a default personal team is created automatically.

### 2. Project

- Click **New project**. Give it a name and short description.

### 3. App configuration

- Project sidebar > **Configuration**.
- Enter the **Bundle ID**. Note: **hyphens are not supported in iOS bundle IDs.**
  So `com.akpersad.snapcount`, not `com.akpersad.snap-count`.
- Add app name and icon (PNG or JPEG, max 200x200). These appear in the Meta AI permission UI.
- This section generates **`MetaAppID`** and **`ClientToken`**.

### 4. Permissions

- **Permissions** tab > request **camera**.
- A written justification is required. It is internal review only, not user-facing.
  Something like: "Captures photographs on user command for on-device analysis. No image data
  leaves the device."

### 5. Wire the credentials in

Paste `MetaAppID` and `ClientToken` into `snapcount/Secrets.xcconfig`, which is gitignored.

---

## Info.plist keys

Corrected against `AGENTS.md`. Earlier notes had two of these wrong.

Inside an `MWDAT` dictionary:

| Key | Value |
|---|---|
| `AppLinkURLScheme` | `snapcount://` (with the `://`; bare `snapcount` goes in `CFBundleURLSchemes`) |
| `MetaAppID` | `0` for developer mode, else from Developer Center |
| `ClientToken` | From Developer Center (not needed for `MetaAppID = 0`) |
| `TeamID` | `U7W22L3PVZ` |
| `Analytics` | dict with `OptOut` = `true`. **Required for this project.** |
| `CrashReporting` | dict with `OptOut` = `true`. **Required for this project.** |

(Corrected 2026-09-23. An earlier version listed a bare `OptOut` here, which the SDK ignores.)

Top level:

| Key | Value |
|---|---|
| `CFBundleURLTypes` | Array matching `AppLinkURLScheme` |
| `UIBackgroundModes` | `bluetooth-peripheral` **and** `external-accessory` |
| `UISupportedExternalAccessoryProtocols` | `com.meta.ar.wearable` |
| `NSBluetoothAlwaysUsageDescription` | Why the app uses Bluetooth |
| `NSLocalNetworkUsageDescription` | Required for Wi-Fi camera streaming |
| `NSBonjourServices` | `_bonjour._tcp` |
| `NSCameraUsageDescription` | For MockDevice feeds |

**Corrections from earlier research:** the background mode is `bluetooth-peripheral` plus
`external-accessory`, not `bluetooth-central`. And `UISupportedExternalAccessoryProtocols` was
missing entirely.

## SPM modules

`https://github.com/facebook/meta-wearables-dat-ios` at 0.9.0.
Tag is `0.9.0` (no `v`). Products: `MWDATCore`, `MWDATCamera`, `MWDATDisplay`,
`MWDATMockDevice`, `MWDATMockDeviceTestClient`. Binary xcframeworks, device + simulator.

Deployment target: iOS 16.0+ per `AGENTS.md`. `SnapCountCore` requires iOS 18 for the modern
Vision API, so the app target is effectively **iOS 18+**.

## API shape

```swift
// Launch
try Wearables.configure()

// Registration (requires internet)
try await Wearables.shared.startRegistration()
for await state in Wearables.shared.registrationStateStream() { /* observe */ }
let status = try await Wearables.shared.requestPermission(.camera)

// Session
let session = try Wearables.shared.createSession(
    deviceSelector: AutoDeviceSelector(wearables: Wearables.shared))
try session.start()
for await state in session.stateStream() where state == .started { break }

// Capture
let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 24)
guard let camera = try session.addCamera(config: config) else { return }
let stream = camera.stream
_ = stream.photoDataPublisher.listen { photoData in /* -> PhotoAnalyzer */ }
stream.start()
stream.capturePhoto(format: .jpeg)

// Display
let display = try session.addDisplay()
try await display.send(FlexBox(direction: .column) { /* Text, Icon */ })
display.start()
```

Also handle the registration callback:

```swift
.onOpenURL { url in Wearables.shared.handleUrl(url) }
```

## Firmware versions are minimums

Meta's version-dependencies page lists **V125** for Ray-Ban Display under DAT 0.9.0 with no
"minimum" or "at least" wording, which reads as a pin. It is not. The companion table in
`../../research/setup-developer-mode.md` is headed "Absolute floors per device" with a **Min
firmware** column, which establishes the page lists floors.

**Device in use is on V128**, which clears the V125 floor. DAT 0.9.0 is the newest tag on the
repo, so there is no later SDK to move to regardless.

This is inference rather than an explicit statement from Meta, but it is cheap to falsify:
registration either succeeds or it does not.

## Gotchas worth pinning to the wall

1. **Developer Mode must be re-enabled after a firmware update.** It survived the V128 update
   this time, but check after any future update.
2. **Registration requires internet.** Do it on land. This is the single biggest pre-trip risk.
3. **Only one third-party app can be registered at a time** in developer mode.
4. **Lower resolution and frame rate give *better* image quality**, because there is less
   Bluetooth compression. Counter-intuitive but documented.
5. Keep listener tokens alive while observing streams, or callbacks stop silently.

## Live docs MCP

Meta hosts a public docs MCP endpoint, no auth required:

```
https://mcp.developer.meta.com/wearables
```

Added and approved at project scope. Sessions get `search_dat_docs` for querying current API
behaviour instead of relying on notes that go stale.
