# Face Recognition Approach

Researched 2026-09-22. Goal: count photos containing one specific person, fully on-device.

## No Apple face-identity API exists

Checked against iOS 26/27. Apple ships face **detection** publicly and does face **identity**
internally (the Photos "People" album), but the identity layer is not exposed to third parties.
Nothing new in the 2025/2026 Vision releases changes this.

So identity is ours to build. Two layers:

| Layer | Who does it | API |
|---|---|---|
| Find faces in an image | Apple Vision | `DetectFaceRectanglesRequest` |
| Decide whose face it is | Us | Core ML embedding + distance |

## Layer 1: detection (Vision)

Free, fast, Neural Engine, no model to ship. The modern Swift API (iOS 18+, current on 27)
is async/await based. Gives bounding boxes plus roll/yaw/pitch and `faceCaptureQuality`.

Use `faceCaptureQuality` to discard blurry or badly-angled faces before spending an embedding
on them. Cheap accuracy win.

## Layer 2: identity (Core ML)

### Chosen: MobileFaceNet trained with ArcFace loss

- Input: 112x112 normalized RGB
- Output: 512-dimensional embedding
- Size: roughly 5 MB
- Compare with cosine similarity, threshold around 0.6-0.7, tuned on real data
- Runs on the Neural Engine

Enroll with 10-20 photos across angles and lighting, store the mean embedding (L2-normalized).

### Rejected: `VNGenerateImageFeaturePrintRequest`

Zero dependencies and pure Apple, but it is a *general image* similarity model, not a face
embedding. Distinguishing one child from another child is exactly its weak case. Keeping it
as a fallback only if the Core ML conversion turns into a time sink.

### Rejected: Create ML binary classifier

Simplest code, but needs a curated negative set and goes stale as a child's face changes.
Embeddings let us re-enroll from a few new photos instead of retraining.

## The hard part: children

Face recognition is materially worse on young children than adults. Two compounding reasons:
less inter-person facial variation, and faces that change fast. Expect to tune the threshold
against real data rather than trusting a published number.

Mitigations:
1. Enroll from recent photos, not old ones.
2. Tune the threshold on a held-out set of her photos plus photos of other similar-aged kids.
3. Bias toward **precision over recall** when in doubt. An undercount is a mildly wrong
   number. An overcount that fires on someone else's kid is the failure that actually matters.
4. Build a review screen so mistakes are visible and correctable.

## Toolchain note

`coremltools` is not installed, and system Python is **3.14.7**, which is likely ahead of
coremltools support. Plan on a 3.11 or 3.12 virtualenv for the conversion step.

Alternative worth trying first: find a pre-converted `.mlmodel` or `.mlpackage` and skip the
Python toolchain entirely. Saves an afternoon if one is available and trustworthy.

## Pipeline

```
photo bytes (from glasses or phone)
  -> Vision: detect faces + quality filter
  -> crop + align each face to 112x112
  -> Core ML: 512-d embedding per face
  -> cosine distance vs enrolled mean
  -> if any face matches: increment today's count
  -> persist { photoID, timestamp, matched: Bool, confidence }
  -> push updated count to the glasses HUD
```

Runs **asynchronously off the capture path**. The count lagging a few seconds is invisible,
and it removes any latency pressure from the camera pipeline.

## Sources

- https://developer.apple.com/wwdc26/guides/ios/
- https://arxiv.org/pdf/1804.07573 (MobileFaceNets)
- https://github.com/likedan/Awesome-CoreML-Models
