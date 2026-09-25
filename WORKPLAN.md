# SnapCount Work Plan

**Single source of truth.** Written so a session with zero prior context can pick up work
immediately. Read this first; it should make re-reading the research files unnecessary for
most tasks.

Last updated: 2026-09-24 (Phase 3d built: on-device enrollment and tuning from the photo picker; open question 8 resolved)

**Next session starts here (2026-09-24):** Phase 3d is built but not yet exercised on a real
iPhone; the user is doing the first device build now. Suggested order from here, given the
departure date: **Phase 4** (PhotoKit ingest, since most cruise photos are phone photos), then
**5** and **6**, with **3e** kept minimal. 5a registration needs internet, so it must happen
on land, followed by the Phase 7 airplane-mode and egress checks. Phases 3d, the doc pass, and
this note are uncommitted unless git says otherwise.

---

## 1. What this is

An iOS app that counts how many photos taken today contain a specific person (the user's
daughter), showing a glanceable count on Meta Ray-Ban Display glasses.

**Deadline: a Disney Cruise departing the week of 2026-09-28.**

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
| Meta AI app version | **289.0.0.21.157** - clears the V282 floor |
| Wearables Developer Center org | Done |
| Wearables Developer Center project | **Done.** MetaAppID + ClientToken in `Secrets.xcconfig` |
| Recognition core (`SnapCountCore`) | **Done, 33 tests passing** |
| Core ML embedding model | **Done.** AdaFace IR-18 fetched, checksum pinned, same-vs-different check passes |
| Enrollment + tuning CLI | **Done.** `snapcount-enroll`, waiting on photos. Optional now that the app tunes on-device |
| Enrollment photos | Not provided. Can now be picked directly on the phone (3d) |
| Xcode app target | **Done.** Generated from `snapcount/project.yml`; builds and runs in the simulator. First physical-iPhone build in progress (2026-09-24) |
| DAT integration | Not started |
| Glasses HUD | Not started |
| Git remote | `git@github.com-personal:akpersad/SnapCount.git`, pushed |
| Docs MCP | **Done.** Approved; `search_dat_docs` tool available in sessions |

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
| **AdaFace IR-18** via Core ML for identity | No Apple face-identity API exists. Vision feature prints are too weak to separate one young child from another. AdaFace's quality-adaptive margin beats ArcFace by ~11% on mixed-quality images, which is exactly what candid shots of a moving child are. |
| Align crops on eye landmarks, not Vision `roll` | Matches the model's expected preprocessing, and avoids Vision's undocumented roll sign convention. |
| Glasses HUD is text and icons only | The `Image` component loads from a URL, which would mean running a local HTTP server. |
| Recognition runs async, off the capture path | A few seconds of lag is invisible and it removes all latency pressure from the camera pipeline. |
| Secrets in gitignored `Secrets.xcconfig` | One pattern for all identifiers beats case-by-case judgement about which are sensitive. |
| `ReferencePhotos/` ignored with **zero exceptions** | An ignore rule protecting a child's photos should have no carve-outs. Guidance lives in `docs/` instead. |
| XcodeGen; `.xcodeproj` generated and gitignored | A readable `project.yml` diffs and reviews cleanly, and a hand-edited `.pbxproj` is where unreviewable config drift hides. |
| Privacy config **fails closed** at launch | The opt-out keys are easy to get subtly wrong (this project already did once). A crash at launch beats an app that quietly reports home. |
| Tuner picks the **middle** of the best-recall threshold range | The low edge hugs the worst impostor in a small tuning set, so the first unseen child scoring slightly higher gets counted. |
| Enrollment and tuning run **on the phone**, from `PhotosPicker` | No Mac, no file transfer, re-enrollable at sea. The CLI shares the same `EnrollmentEvaluator`, so the two cannot disagree. (Open question 8.) |

---

## 4. Verified facts

Researched and confirmed. Do not re-derive.

### Privacy and data path
- Camera streaming: glasses to phone over **local-network Wi-Fi (Bonjour)**, or BLE without
  streaming. **Image data does not transit Meta's cloud.**
- Meta SDK **analytics and crash reporting are ON by default**. Each is disabled by its own
  **nested** dictionary: `MWDAT > Analytics > OptOut = true` and
  `MWDAT > CrashReporting > OptOut = true`. A bare `OptOut` directly under `MWDAT` is **ignored**
  (earlier docs had this wrong; source is the SDK repo README at tag 0.9.0).
  `PrivacyChecks.swift` halts the app at launch if either is missing.

### Versions
- DAT **0.9.0** is the newest tag (named `0.9.0`, no `v` prefix). No 1.0 exists.
- Firmware numbers on Meta's version page are **floors, not pins**. Display floor is V125.
- Meta AI app needs **V282**.
- Developer Mode must be re-enabled after firmware updates (did not trigger this time).

### SDK surface
- Modules: `MWDATCore`, `MWDATCamera`, `MWDATDisplay`, `MWDATMockDevice`,
  `MWDATMockDeviceTestClient`. All binary xcframeworks with **device and simulator** slices.
- `Permission` enum has exactly **one** case: `.camera`. Earlier research claiming microphone
  access is **unverified** and may be marketing copy. Irrelevant here; `snapcount` needs no audio.
- Display components: `FlexBox`, `Text`, `Image`, `Button`, `ButtonGroup`, `Icon`,
  `VideoPlayer`. Full view re-sent on every update; no partial updates.
- `MetaAppID` can be **`0`** in developer mode
- Only **one** third-party app can be registered at a time
- Lower resolution and frame rate give *better* image quality (less Bluetooth compression)
- MockDeviceKit does **not** simulate the display

### Info.plist keys
Inside an `MWDAT` dictionary: `AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`,
`Analytics` (dict: `OptOut`), `CrashReporting` (dict: `OptOut`). The live file is
`snapcount/SnapCount/Info.plist`.
Top level: `CFBundleURLTypes`, `UIBackgroundModes` (`bluetooth-peripheral` **and**
`external-accessory`), `UISupportedExternalAccessoryProtocols` (`com.meta.ar.wearable`),
`NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices`
(`_bonjour._tcp`), `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` (Apple, for
Phase 4 PhotoKit; `PhotosPicker` enrollment does not need it).

### Environment
- Xcode 27, Swift 6.4, iOS 27 SDK, macOS 26.7
- Python 3.14.7, no coremltools. **Not needed**: the model is pre-converted.
- XcodeGen is installed (`/opt/homebrew/bin/xcodegen`). `SnapCount.xcodeproj` is generated
  and gitignored; `project.yml` is the source.
- Simulator: iPhone 18 Pro, iOS 27, UDID `F0AA0FF7-F299-472E-9A1D-1AD0EEB905B3`. Build with
  `-destination 'generic/platform=iOS Simulator'`; named destinations like "iPhone 16 Pro" fail.
- `~/.bash_profile` overrides `cd` so it returns non-zero in non-interactive shells.
  **`cd x && y` silently skips `y`.** Use absolute paths or `--package-path`.

---

## 5. Phases

Ordered by dependency. Phases 1 to 4 need nothing from Meta.

### Phase 0: Developer Center configuration  [DONE]

Team ID, Bundle ID `com.akpersad.snapcount`, and Universal link `snapcount://` saved.
`MetaAppID` and `ClientToken` are in `snapcount/Secrets.xcconfig` (gitignored, verified absent
from all commits).

**Camera access** toggle is on with a rationale. Phase 0 is fully complete; Phase 5 is
unblocked on the Meta side.

---

### Phase 1: Recognition core  [DONE]

`snapcount/SnapCountCore`, a Swift package that builds and tests from the command line with no
Xcode project, no glasses, and no Developer Center account. **33 tests passing.**

| File | Role |
|---|---|
| `Models.swift` | `FaceEmbedding` (cosine, centroid), `DetectedFace`, `PhotoRecord` |
| `FaceDetector.swift` | Vision detection, quality/size/yaw filters, landmark alignment |
| `FaceEmbedder.swift` | Protocol, Vision feature-print fallback, Core ML implementation |
| `EnrollmentStore.swift` | `EnrolledPerson`, JSON persistence, backup exclusion, `Enroller`, `EmbeddedFace` |
| `EnrollmentEvaluator.swift` | Centroid + leave-one-out tuning over embeddings. Shared by the app and the CLI |
| `PhotoAnalyzer.swift` | Per-photo orchestration, `DailyTally` |
| `ThresholdTuner.swift` | Precision-first threshold sweep, midpoint of the best-recall plateau |
| `AdaFace.swift` | Verified model contract (`AdaFaceIR18`), compiles `.mlpackage` on the fly |
| `ImageLoading.swift` | EXIF-upright, 2048 px-bounded decode. Use it for PhotoKit data too |
| `snapcount-enroll/main.swift` | Desk-side CLI for 2b + 2c over `ReferencePhotos/` |

```
swift build --package-path snapcount/SnapCountCore
swift test  --package-path snapcount/SnapCountCore
```

---

### Phase 2: Model and enrollment  [2a DONE; 2b/2c tooling done in app and CLI, waiting on photos]

- [x] **2a. Fetch and wire the AdaFace IR-18 Core ML model.** Done. Checksum pinned in
      `fetch-model.sh`. Contract, read from the compiled graph (not guessed):
      input `face_image`, 112x112 Image, **BGR**; the graph applies `x * 2/255 - 1` itself, so
      **do not pre-normalize**. Output `embedding`, Float16 `[1, 512]`, L2-normalized in-graph.
      Encoded in `AdaFaceIR18`. Sanity check on public-domain official portraits
      (`snapcount/Models/SanityFaces/`, gitignored): same-person 0.67-0.72, worst
      different-person pair 0.21.
- [ ] **2b + 2c. Enroll and tune.** Primary path is now **in the app** (3d): pick her photos
      and other children in `EnrollmentView`, review, save. The CLI below does the same thing
      at a desk and prints more detail; use it only if photos are on the Mac:
      ```
      swift run --package-path snapcount/SnapCountCore snapcount-enroll
      ```
      Reads `ReferencePhotos/daughter/` and `ReferencePhotos/negatives/`, writes
      `snapcount/Enrollment/enrollment.json` (gitignored) including the tuned `matchThreshold`.
      Her photos are scored **leave-one-out** so the threshold is not optimistic. Every face in
      a negatives photo is scored, not just the largest. Prints the weakest reference photos
      and the most similar strangers. Exit 2 means no threshold reached precision (see below).
      *Acceptance:* `sampleCount` >= 10 and a threshold at >=0.98 precision with usable recall.
      **If no threshold qualifies, the reference set is not discriminative and needs better
      photos.** That is a real possible outcome, not a bug.
      Photo guidance lives in `snapcount/docs/enrollment-photos.md`. Short version: 15-30 of
      her, 30+ of **other children her age** (never her, and not adults).

**Blocked on:** the user picking photos on the phone (or, for the CLI, putting them in
`snapcount/ReferencePhotos/{daughter,negatives}/`). The acceptance bar is the same either way.

---

### Phase 3: iOS app shell  [3a-3d DONE; 3e NEXT]

- [x] **3a. App target.** `snapcount/project.yml` (XcodeGen): iOS 18, Swift 6 strict
      concurrency, bundle ID `com.akpersad.snapcount`, `Secrets.xcconfig` as the config file.
      The model is a source, so Xcode compiles it to `AdaFace_IR18.mlmodelc` in the bundle.
      App sources in `snapcount/SnapCount/`: `SnapCountApp`, `PrivacyChecks`,
      `RecognitionModel`, and a `ContentView` status screen (model ready, enrollment state).
- [x] **3b. DAT SPM dependency**, `exactVersion: 0.9.0`, linking Core, Camera, Display.
      Imported but not yet called; `Wearables.configure()` is Phase 5a.
- [x] **3c. Full Info.plist** with both nested opt-outs. Verified in the built bundle, and
      the app launches past `PrivacyChecks` in the simulator.
- [x] **3d. Enrollment UI.** `EnrollmentView` + `EnrollmentFlow`: two `PhotosPicker`s (her
      photos, other children), each photo decoded, embedded, and dropped one at a time. Tuning
      runs on the phone via `EnrollmentEvaluator` (shared with the CLI, leave-one-out). The
      result screen shows the threshold, usable counts, and the 112 px crops of her least
      typical photos and the closest strangers, so a sibling picked as "largest face" is
      visible. Save, start over, delete. `AppModel` holds the model and enrollment app-wide and
      rejects an enrollment made with a different model identifier.
      *Built and launched in the simulator; the picker flow has not been tapped through yet.
      First real run should be on the phone with real photos.*
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

### Phase 5: DAT integration  [UNBLOCKED]

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

- [x] Analytics and crash reporting opt-outs in the plist, enforced at launch by `PrivacyChecks`
- [ ] Opt-outs confirmed by proxy on a real device (covered by the egress check below)
- [ ] Proxy a full capture session, confirm **zero unexpected egress**
- [ ] Confirm enrollment data excluded from backup
- [ ] If the CLI was used, delete `ReferencePhotos/` after enrollment is verified (in-app
      enrollment reads the user's own library through the picker and copies nothing)
- [ ] **Airplane-mode end-to-end test** (proves both the privacy claim and sea readiness)
- [ ] Measure battery with the stream running
- [x] Meta AI app clears the V282 floor (289.0.0.21.157, 2026-09-22). Recheck after any update

---

## 6. Open questions

| # | Question | How to resolve | Blocks |
|---|---|---|---|
| 1 | ~~Universal link vs custom URL scheme?~~ **RESOLVED.** The field accepted `snapcount://`, so no hosted `apple-app-site-association` is needed. | Done | none |
| 2 | ~~Does camera permission work with `MetaAppID = 0`?~~ **MOOT.** A real `MetaAppID` was issued and camera permission is declared and toggled on. | Done | none |
| 6 | ~~AdaFace feature names and normalization?~~ **RESOLVED.** `face_image` (BGR) to `embedding`; [-1, 1] normalization is inside the graph. See 2a. | Done | none |
| 7 | Pretrained-weight licensing. The AdaFace repo is MIT, but the weights derive from datasets with research-use restrictions. | Fine for a personal, undistributed app. Needs a real answer before any release. Distribution is closed during the preview anyway. | Distribution only |
| 3 | Does photo capture require a **started** stream? The API does require a `Stream` (capture is `stream.capturePhoto`), but whether `stream.start()` must be running is untested. | Test on device in 5c. Determines whether all-day capture is battery-viable. | Phase 5c, battery item in 7 |
| 8 | ~~How does the tuned threshold reach the phone?~~ **RESOLVED: (a).** The app takes a negatives set and tunes on-device with the same `EnrollmentEvaluator` the CLI uses. No Mac or file transfer needed. | Done | none |
| 4 | Are raw swipe/pinch events exposed, or only `Button` taps? | Button taps are sufficient, so this is informational. | none |
| 5 | Is text input available on device? | Not needed by this app. | none |

---

## 7. Configuration screen values

For the Wearables Developer Center **Configuration** page, iOS tab:

```
Team ID:        U7W22L3PVZ        [saved]
Bundle ID:      com.akpersad.snapcount   [saved]
Universal link: snapcount://      [saved]
```

**Watch out:** Meta's generated plist snippet uses their placeholder `myexampleapp://`. It must
be changed to `snapcount://` to match what was saved. See `snapcount/docs/info-plist.md`.

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
   If `snapcount/Models/` is missing (fresh clone), run `snapcount/Scripts/fetch-model.sh`.
3. `xcodegen generate --spec snapcount/project.yml`, then build:
   `xcodebuild -project snapcount/SnapCount.xcodeproj -scheme SnapCount -destination 'generic/platform=iOS Simulator' build`
4. Check section 2 for state and section 5 for the next unchecked item.
5. Remember the `cd` gotcha in section 4.

Deeper detail, only if needed:
- `snapcount/Scripts/fetch-model.sh` - downloads AdaFace IR-18 (gitignored, not committed)
- `snapcount/SnapCount/Info.plist` - **the live Info.plist** (`docs/info-plist.md` explains it)
- `snapcount/docs/setup-walkthrough.md` - Developer Center specifics
- `snapcount/docs/privacy-architecture.md` - the no-egress checklist
- `snapcount/research/dat-api-findings.md` - the 0.9 API surface
- `snapcount/research/face-recognition-approach.md` - model choice, child-accuracy problem
