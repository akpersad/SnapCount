# Enrollment Photos

Photos go in `snapcount/ReferencePhotos/`, which is **gitignored in its entirety with no
exceptions**. Nothing in that directory is ever committed or uploaded. This guidance lives in
`docs/` precisely so the ignore rule can stay absolute rather than needing a carve-out.

## `daughter/`

10 to 20 photos for enrollment. What makes a good set:

- **Recent.** A child's face changes fast, and an old reference matches poorly.
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

20 or more is useful. Cousins, classmates, friends. They do not need to be good photos.

## What happens to these

Enrollment reads them once, computes a 512-float mean embedding, and writes only that vector
to the app container. The photos themselves are never copied anywhere, never transmitted, and
should be deleted from here once enrollment is verified.
