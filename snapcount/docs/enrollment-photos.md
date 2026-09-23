# Enrollment Photos

Photos go in `snapcount/ReferencePhotos/`, which is **gitignored in its entirety with no
exceptions**. Nothing in that directory is ever committed or uploaded. This guidance lives in
`docs/` precisely so the ignore rule can stay absolute rather than needing a carve-out.

## `daughter/`

15 to 30 photos for enrollment. At least 10 must survive the face filters (the enrollment
tool reports which ones were skipped and why). What makes a good set:

- **Recent.** From the last year. A child's face changes fast, and an old reference matches poorly.
- **Varied angles.** Straight on, three-quarter left, three-quarter right. Skip full profile,
  the detector discards anything beyond 45 degrees of yaw.
- **Varied lighting.** Indoor, outdoor, shade. Not all from one afternoon.
- **Her face reasonably large in frame.** Faces under ~6% of the short edge are filtered out.
- **Ideally only her.** The enroller takes the largest face per photo, so a group shot where
  someone else is closer to the camera would poison the reference.

Neutral and smiling both help. Sunglasses and hats do not.

## `negatives/`

Photos containing **other children of similar age**, for threshold tuning. This set is what
proves the threshold actually discriminates rather than matching any child. Without it the
cut-off is guesswork, and the failure mode is counting someone else's kid.

30 or more. Cousins, classmates, friends. They do not need to be good photos, and group
shots are welcome: every face in a negatives photo is scored, not just the largest.

**Never include her**, not even in the background; it would teach the tuner that her face is
a stranger's. And **not adults**: an adult is easy to tell apart from a child, so adult
negatives make the threshold look far safer than it is.

## What happens to these

`swift run --package-path snapcount/SnapCountCore snapcount-enroll` reads them once, computes a
512-float mean embedding plus a tuned match threshold, and writes only those to
`snapcount/Enrollment/enrollment.json` (gitignored). The photos themselves are never copied
anywhere, never transmitted, and should be deleted from here once enrollment is verified.

How that threshold reaches the phone is WORKPLAN open question 8.
