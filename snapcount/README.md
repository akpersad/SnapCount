# snapcount

Count how many photos taken today contain a specific person. Fully on-device.

Working name, rename freely.

## Why it exists

Immediate goal: a Disney Cruise departing late September 2026. A glanceable count on the
Ray-Ban Display of how many photos of my daughter I have taken today.

Hard requirement: **her face never leaves the device.** No cloud recognition, no uploads,
no third-party services. See `docs/privacy-architecture.md` for how that is enforced rather
than merely intended.

## Architecture

```
  Ray-Ban Display  ──(local Wi-Fi / BT)──▶  iPhone app  ──(BT)──▶  Ray-Ban Display
     camera                                   │                       HUD: "7 today"
                                              │
                                   ┌──────────┴──────────┐
                                   │  Vision: detect     │
                                   │  Core ML: embed     │  all local,
                                   │  cosine: match      │  Neural Engine
                                   └─────────────────────┘
```

Recognition runs **asynchronously off the capture path**. A few seconds of lag in the count
is invisible, and it removes all latency pressure from the camera pipeline.

## Key decisions made

| Decision | Choice | Why |
|---|---|---|
| SDK path | Device Access Toolkit (native) | Only path with camera. Works offline. |
| Face detection | Apple Vision | Free, on-device, no model to ship |
| Face identity | **AdaFace IR-18** via Core ML | No Apple identity API exists; feature prints are too weak for children. AdaFace beats ArcFace on mixed-quality images, which is what candid shots of a moving child are. |
| Glasses HUD | Text and icons only, no images | `Image` loads from URL; avoiding it keeps everything local |
| Meta telemetry | Off | `MWDAT > Analytics > OptOut` and `MWDAT > CrashReporting > OptOut`, enforced at launch |
| Photo storage | App container, excluded from backup | Keeps biometric data out of iCloud |

## Build order

**See [`../WORKPLAN.md`](../WORKPLAN.md) for the authoritative phase list, current status, and
acceptance criteria.** It is not duplicated here, so the two cannot drift apart.

The sequencing principle, which will not change: the face recognition is the **known**
quantity and the 0.9 preview SDK is the **unknown** one. So the recognition pipeline is built
first, as a plain iOS app testable at a desk with no glasses. The glasses bolt on last as a
display and trigger layer. If DAT falls through, this still lands as a working phone app.

Phases 1 to 4 need nothing from Meta. The Developer Center project is done, so nothing is
blocked on Meta.

## Layout

- `SnapCountCore/` - the recognition pipeline, as a Swift package. Builds and tests from the
  command line with no Xcode project, no glasses, and no Developer Center account. Also holds
  the `snapcount-enroll` CLI.
- `SnapCount/` - the iOS app (sources, `Info.plist`, assets).
- `project.yml` - XcodeGen spec. `SnapCount.xcodeproj` is generated from it and gitignored.
- `Scripts/fetch-model.sh` - downloads the AdaFace model into `Models/` (gitignored).
- `research/dat-api-findings.md` - the 0.9 API surface, verified 2026-09-22
- `research/face-recognition-approach.md` - model choice and the child-accuracy problem
- `docs/privacy-architecture.md` - the no-egress checklist

## Running it

```
Scripts/fetch-model.sh                      # once per clone
swift test --package-path SnapCountCore     # core + model tests
xcodegen generate --spec project.yml        # then open SnapCount.xcodeproj, or:
xcodebuild -project SnapCount.xcodeproj -scheme SnapCount \
  -destination 'generic/platform=iOS Simulator' build
```

The app build needs `Secrets.xcconfig` (copy `Secrets.xcconfig.template`).

Note: this repo's shell has a `cd` override in `~/.bash_profile` that returns non-zero in
non-interactive shells, which silently breaks `cd x && y`. Use absolute paths or
`--package-path`.

### What exists so far

| File | Role |
|---|---|
| `Models.swift` | `FaceEmbedding` (cosine, centroid), `DetectedFace`, `PhotoRecord` |
| `FaceDetector.swift` | Vision detection, quality/size/yaw filtering, landmark alignment |
| `FaceEmbedder.swift` | Protocol, Vision feature-print fallback, Core ML implementation |
| `EnrollmentStore.swift` | `EnrolledPerson`, JSON persistence, backup exclusion, `Enroller` |
| `PhotoAnalyzer.swift` | Per-photo orchestration, `DailyTally` |
| `ThresholdTuner.swift` | Precision-first threshold sweep over labelled data |
| `AdaFace.swift` | Verified AdaFace IR-18 model contract and loader |
| `ImageLoading.swift` | EXIF-upright, size-bounded decode for the pipeline |
| `snapcount-enroll` (executable) | Offline enrollment + leave-one-out threshold tuning |

27 tests passing, 3 of which run the real AdaFace model and skip if it is not fetched. The alignment geometry is pinned by six of them, including both roll
directions and extreme up/downscale, because a silently misaligned crop degrades every
embedding without ever failing visibly.

### Notable implementation decision

Crops are aligned by mapping the two detected eye centres onto the canonical ArcFace
reference positions with a similarity transform. Two reasons:

1. It is the standard ArcFace-convention preprocessing that MobileFaceNet, ArcFace, and
   AdaFace are all trained with, so matching it is worth real accuracy.
2. It avoids depending on Vision's `roll` sign convention, which is not documented clearly
   enough to trust without a real rotated face to test against.

Eyes are ordered by x rather than by Vision's left/right labels, which keeps the transform
independent of whose perspective those labels use. Valid for |roll| < 90 degrees; beyond that
the capture-quality filter has almost certainly dropped the face anyway.

## Known risks

1. **Accuracy on children.** The core technical risk. Less inter-person variation, faces
   change fast. Threshold must be tuned on real data. Bias toward precision.
2. **Battery.** Photo capture appears to require a running stream. An all-day capture mode
   may be expensive. Unmeasured.
3. **Timeline.** Departure is the week of 2026-09-28, on a pre-1.0 SDK. Phases 1-4 are
   phone-only and within reach. Phases 5-6 depend on how cleanly registration goes.
4. ~~**coremltools vs Python 3.14.**~~ Resolved: a pre-converted model is used, so no Python
   toolchain is needed.
