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

### Chosen: AdaFace IR-18

Changed from MobileFaceNet on 2026-09-22, after finding a pre-converted Core ML build.

- Input: 112x112 RGB, ArcFace-convention 5-point alignment (which `FaceDetector` already does)
- Output: 512-dimensional embedding
- Compare with cosine similarity, threshold tuned on real data
- Runs on the Neural Engine

**Why AdaFace over ArcFace/MobileFaceNet.** AdaFace (CVPR 2022) uses a quality-adaptive
margin: it weights training emphasis by image quality, de-emphasising unidentifiable samples
instead of letting them drag the model. On mixed-quality benchmarks (IJB-B, IJB-C) it cuts
error 11% and 9% against the next best method.

That is directly on point. Candid photographs of a moving child, half of them captured from
glasses over a compressed Bluetooth link, are a mixed-quality set almost by definition. This
is the failure mode we are most exposed to.

**The tradeoff: size.** IR-18 is a ResNet-18 backbone, 44.5 MB zipped, versus roughly 5 MB for
MobileFaceNet. Irrelevant for a personally sideloaded developer-mode app. If size ever
mattered, MobileFaceNet remains the fallback and the pipeline needs no changes to swap it,
since `FaceEmbedder` is a protocol and `Enrollment` records which embedder built it.

Source: `john-rocky/CoreML-Models`, release `adaface-v1`, asset `AdaFace_IR18.mlpackage.zip`.
Fetch with `snapcount/Scripts/fetch-model.sh`. The model is gitignored, not committed.

**Licensing is an open item.** The AdaFace repo is MIT, but pretrained weights derive from
datasets (MS1MV2, WebFace4M and similar) that carry research-use restrictions of their own.
For a personal app that is never distributed, and which cannot be distributed anyway while
Meta's publishing is closed, this is fine. It would need a real answer before any release.

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
