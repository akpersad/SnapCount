# SnapCount Work Plan

**Single source of truth.** Written so a session with zero prior context can pick up work
immediately. Read this first; it should make re-reading the research files unnecessary for
most tasks.

Last updated: 2026-09-22

---

## 1. What this is

An iOS app that counts how many photos taken today contain a specific person (the user's
daughter), showing a glanceable count on Meta Ray-Ban Display glasses.

**Deadline: a Disney Cruise departing the week of 2026-09-28.** Roughly six days.

### Two hard constraints, both non-negotiable

1. **Nothing leaves the device.** A child's face is being processed. No cloud recognition, no
   uploads, no third-party services, no telemetry. This is the reason the project exists in
   this form.
2. **Must work fully offline.** Internet at sea is metered, slow, and expensive. Everything
   needed must be loaded before boarding.

Any proposal involving a cloud API, hosted model, or live data feed is wrong for this project.
Test every feature in airplane mode.

---

## 2. Status snapshot

| Area | State |
|---|---|
| Meta developer account | Done |
| Developer Mode in Meta AI app | **On** (verified still on after V128 firmware update) |
| Glasses firmware | **V128** (clears the V125 floor for DAT 0.9) |
| Meta AI app version | **UNVERIFIED** - needs V282 |
| Wearables Developer Center org | Done |
| Wearables Developer Center project | Created; **Configuration pending** |
| Recognition core (`SnapCountCore`) | **Done, 23 tests passing** |
| Core ML embedding model | Not sourced |
| Enrollment photos | Not provided |
| Xcode app target | Not created |
| DAT integration | Not started |
| Glasses HUD | Not started |
| Git remote | `git@github.com-personal:akpersad/SnapCount.git`, pushed |
| Docs MCP | Added at project scope, **pending approval** |

---

## 3. Decisions already made

Recorded so they are not re-litigated. Each has a reason; revisit only if the reason changes.

| Decision | Reason |
|---|---|
| Native Device Access Toolkit, not Web Apps | Only path with camera. Also the only one that works offline, since the app runs on the phone and the glasses are a Bluetooth peripheral. |
| Count glasses captures **and** phone library photos | Most cruise photos will be taken on the phone. Glasses-only would undercount badly. |
| Manual capture via glasses button tap | Predictable battery, no surprise captures of other people's children, and matches the confirmed `Button` tap-handler API. |
| Push both count accuracy and glasses HUD | User chose not to compromise on either. |
| Apple Vision for detection | Free, on-device, Neural Engine, no model to ship. |
| MobileFaceNet/ArcFace via Core ML for identity | No Apple face-identity API exists. Vision feature prints are too weak to separate one young child from another. |
| Align crops on eye landmarks, not Vision `roll` | Matches the model's expected preprocessing, and avoids Vision's undocumented roll sign convention. |
| Glasses HUD is text and icons only | The `Image` component loads from a URL, which would mean running a local HTTP server. |
| Recognition runs async, off the capture path | A few seconds of lag is invisible and it removes all latency pressure from the camera pipeline. |
| Secrets in gitignored `Secrets.xcconfig` | One pattern for all identifiers beats case-by-case judgement about which are sensitive. |
| `ReferencePhotos/` ignored with **zero exceptions** | An ignore rule protecting a child's photos should have no carve-outs. Guidance lives in `docs/` instead. |

---

## 4. Verified facts

Researched and confirmed. Do not re-derive.

### Privacy and data path
- Camera streaming: glasses to phone over **local-network Wi-Fi (Bonjour)**, or BLE without
  streaming. **Image data does not transit Meta's cloud.**
- Meta SDK **analytics and crash reporting are ON by default**. Disable with `OptOut = true`
  in the `MWDAT` Info.plist dictionary. Crash reporting needs the same treatment.

### Versions
- DAT **0.9.0** is the newest tag. No 1.0 exists.
- Firmware numbers on Meta's version page are **floors, not pins**. Display floor is V125.
- Meta AI app needs **V282**.
- Developer Mode must be re-enabled after firmware updates (did not trigger this time).

### SDK surface
- Modules: `MWDATCore`, `MWDATCamera`, `MWDATDisplay`, `MWDATMockDevice`
- `Permission` enum has exactly **one** case: `.camera`
- Display components: `FlexBox`, `Text`, `Image`, `Button`, `ButtonGroup`, `Icon`,
  `VideoPlayer`. Full view re-sent on every update; no partial updates.
- `MetaAppID` can be **`0`** in developer mode
- Only **one** third-party app can be registered at a time
- Lower resolution and frame rate give *better* image quality (less Bluetooth compression)
- MockDeviceKit does **not** simulate the display

### Info.plist keys
Inside an `MWDAT` dictionary: `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`,
`OptOut`.
Top level: `CFBundleURLTypes`, `UIBackgroundModes` (`bluetooth-peripheral` **and**
`external-accessory`), `UISupportedExternalAccessoryProtocols` (`com.meta.ar.wearable`),
`NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`
(`_bonjour._tcp`), `NSCameraUsageDescription`.

### Environment
- Xcode 27, Swift 6.4, iOS 27 SDK, macOS 26.7
- Python 3.14.7, **no coremltools** (3.14 likely unsupported; plan a 3.11/3.12 venv)
- `~/.bash_profile` overrides `cd` so it returns non-zero in non-interactive shells.
  **`cd x && y` silently skips `y`.** Use absolute paths or `--package-path`.

---

## 5. Phases

Ordered by dependency. Phases 1 and 2 need nothing from Meta.

### Phase 0: Developer Center configuration  [BLOCKED ON USER]

Fill the Configuration screen. See section 7 for exact values.

- [ ] Team ID, Bundle ID, Universal link
- [ ] Toggle **Camera access** on, add rationale
- [ ] Capture the generated `MetaAppID` and `ClientToken` into `snapcount/Secrets.xcconfig`

**Acceptance:** Secrets.xcconfig has non-empty `META_APP_ID` and `META_CLIENT_TOKEN`.

---

### Phase 1: Recognition core  [DONE]

`snapcount/SnapCountCore`, a Swift package that builds and tests from the command line with no
Xcode project, no glasses, and no Developer Center account. **23 tests passing.**

| File | Role |
|---|---|
| `Models.swift` | `FaceEmbedding` (cosine, centroid), `DetectedFace`, `PhotoRecord` |
| `FaceDetector.swift` | Vision detection, quality/size/yaw filters, landmark alignment |
| `FaceEmbedder.swift` | Protocol, Vision feature-print fallback, Core ML implementation |
| `EnrollmentStore.swift` | `EnrolledPerson`, JSON persistence, backup exclusion, `Enroller` |
| `PhotoAnalyzer.swift` | Per-photo orchestration, `DailyTally` |
| `ThresholdTuner.swift` | Precision-first threshold sweep |

```
swift build --package-path snapcount/SnapCountCore
swift test  --package-path snapcount/SnapCountCore
```

---

### Phase 2: Model and enrollment  [NEXT, unblocked except for photos]

- [ ] **2a. Source a MobileFaceNet Core ML model.** Try a pre-converted `.mlpackage` first.
      Fall back to ONNX + coremltools in a Python 3.11/3.12 venv.
      *Acceptance:* `CoreMLFaceEmbedder` returns a 512-d embedding for a test crop; two photos
      of the same person score higher than two of different people.
- [ ] **2b. Enrollment CLI or test harness.** Read `ReferencePhotos/daughter/`, build the
      centroid, write `enrollment.json`.
      *Acceptance:* enrollment.json exists with `sampleCount` >= 10.
- [ ] **2c. Tune the threshold.** Run `ThresholdTuner` over daughter vs `negatives/`.
      *Acceptance:* a threshold reaching >=0.98 precision with usable recall. **If
      `recommend()` returns nil, the reference set is not discriminative and needs better
      photos.** That is a real possible outcome, not a bug.

**Blocked on:** user providing photos in `snapcount/ReferencePhotos/{daughter,negatives}/`.

---

### Phase 3: iOS app shell

- [ ] **3a. Create the Xcode app target.** iOS 18+ (SnapCountCore needs the modern Vision API).
      Bundle ID `com.akpersad.snapcount`. Wire `Secrets.xcconfig`.
- [ ] **3b. Add the DAT SPM dependency** at 0.9.0.
- [ ] **3c. Full Info.plist**, including `OptOut = true`.
- [ ] **3d. Enrollment UI** - pick photos, show the computed reference, allow re-enrollment.
- [ ] **3e. Review screen** - list today's photos with scores, allow user override. Surface
      `DailyTally.uncertain()` first.

*Acceptance:* app runs on device, enrolls from the photo picker, counts correctly from the
library.

---

### Phase 4: PhotoKit ingest

- [ ] **4a.** Enumerate today's photos, run the pipeline, dedupe against glasses captures.
- [ ] **4b.** Incremental background processing with progress.

*Acceptance:* count reflects phone photos within a minute of taking them.

---

### Phase 5: DAT integration  [BLOCKED ON PHASE 0]

- [ ] **5a.** `Wearables.configure()`, `startRegistration()`, `.onOpenURL` callback handling.
- [ ] **5b.** Request `.camera` permission; build and test the denied path.
- [ ] **5c.** `DeviceSession`, `addCamera`, `photoDataPublisher`, `capturePhoto(.jpeg)`.
- [ ] **5d.** Feed captures into `PhotoAnalyzer`.

*Acceptance:* pinch on glasses produces a photo that lands in the tally.

**Registration requires internet. Must be done on land.**

---

### Phase 6: Glasses HUD

- [ ] **6a.** `session.addDisplay()`, `FlexBox` + `Text` + `Icon` showing the count.
- [ ] **6b.** `Button` with tap handler to trigger capture.
- [ ] **6c.** Re-send the full view on count change.

*Acceptance:* count visible on glasses, updates within seconds of a capture.

---

### Phase 7: Harden and verify  [MUST COMPLETE BEFORE DEPARTURE]

- [ ] `OptOut = true` confirmed; crash reporting disabled
- [ ] Proxy a full capture session, confirm **zero unexpected egress**
- [ ] Confirm enrollment data excluded from backup
- [ ] Delete reference photos after enrollment is verified
- [ ] **Airplane-mode end-to-end test** (proves both the privacy claim and sea readiness)
- [ ] Measure battery with the stream running
- [ ] Confirm Meta AI app is on V282

---

## 6. Open questions

| # | Question | How to resolve | Blocks |
|---|---|---|---|
| 1 | Universal link vs custom URL scheme? Docs conflict: the iOS guide shows `myexampleapp://`, other text says it "should be a universal link registered with Apple," and the Developer Center has a Universal link field. | Try saving Configuration with the custom scheme or blank first. If registration callback fails, host an `apple-app-site-association` on Vercel. **Only affects registration, which happens on land, so it does not threaten offline operation.** | Phase 5 |
| 2 | Does camera permission work with `MetaAppID = 0`? | Empirical. If the prompt never fires, the permission is probably not declared on the project. | Phase 5 |
| 3 | Does photo capture require a running stream? | Read the 0.9 reference or test. Determines whether all-day capture is battery-viable. | Phase 6 |
| 4 | Are raw swipe/pinch events exposed, or only `Button` taps? | Button taps are sufficient, so this is informational. | none |
| 5 | Is text input available on device? | Not needed by this app. | none |

---

## 7. Configuration screen values

For the Wearables Developer Center **Configuration** page, iOS tab:

```
Team ID:        U7W22L3PVZ
Bundle ID:      com.akpersad.snapcount
Universal link: see open question 1 - try blank or a custom scheme first
```

Note the banner: iOS bundle ID and Android package name must be identical. Hyphens are not
supported in iOS bundle IDs.

**Camera access:** toggle ON. Rationale (internal review only, not user-facing):

> Captures photographs on explicit user command and analyzes them on-device to count how many
> photos contain a specific enrolled family member. All face detection and recognition run
> locally via Apple Vision and Core ML. No image data or biometric data is transmitted off the
> device or to any third party.

After saving, the page issues `MetaAppID` and `ClientToken`. Put both in
`snapcount/Secrets.xcconfig` (gitignored).

---

## 8. Resuming a cleared session

1. Read this file.
2. `swift test --package-path snapcount/SnapCountCore` to confirm the core is green.
3. Check section 2 for state and section 5 for the next unchecked item.
4. Remember the `cd` gotcha in section 4.

Deeper detail, only if needed:
- `snapcount/docs/setup-walkthrough.md` - Developer Center and Info.plist specifics
- `snapcount/docs/privacy-architecture.md` - the no-egress checklist
- `snapcount/research/dat-api-findings.md` - the 0.9 API surface
- `snapcount/research/face-recognition-approach.md` - model choice, child-accuracy problem
