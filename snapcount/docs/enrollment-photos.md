# Enrollment Photos

Two ways to enroll, same rules for choosing photos:

- **On the phone (primary).** SnapCount > Enrollment. Pick her photos and other children's
  photos straight from the library. The same guidance below applies to each picker.
- **At a desk (optional).** Put photos in `snapcount/ReferencePhotos/` and run the CLI. That
  directory is **gitignored in its entirety with no exceptions**. Nothing in it is ever
  committed or uploaded. This guidance lives in `docs/` precisely so the ignore rule can stay
  absolute rather than needing a carve-out.

## Her photos (`daughter/`)

15 to 30 photos for enrollment. At least 10 must survive the face filters (the enrollment
screen and the CLI both report how many were skipped). What makes a good set:

- **Recent.** From the last year. A child's face changes fast, and an old reference matches poorly.
- **Varied angles.** Straight on, three-quarter left, three-quarter right. Skip full profile,
  the detector discards anything beyond 45 degrees of yaw.
- **Varied lighting.** Indoor, outdoor, shade. Not all from one afternoon.
- **Her face reasonably large in frame.** Faces under ~6% of the short edge are filtered out.
- **Ideally only her.** The enroller takes the largest face per photo, so a group shot where
  someone else is closer to the camera would poison the reference. The app's result screen
  shows the face crop it picked from her least typical photos, so check those.

Neutral and smiling both help. Sunglasses and hats do not.

## Other children (`negatives/`)

Photos containing **other children of similar age**, for threshold tuning. This set is what
proves the threshold actually discriminates rather than matching any child. Without it the
cut-off is guesswork, and the failure mode is counting someone else's kid.

30 or more. Cousins, classmates, friends. They do not need to be good photos, and group
shots are welcome: every face in a negatives photo is scored, not just the largest.

**Never include her**, not even in the background; it would teach the tuner that her face is
a stranger's. And **not adults**: an adult is easy to tell apart from a child, so adult
negatives make the threshold look far safer than it is.

## What happens to these

Either path reads each photo once, computes a 512-float mean embedding plus a tuned match
threshold (her photos scored leave-one-out), and persists only those. Nothing is transmitted.

- **App:** photos are read through the system picker, one at a time, and never copied. Small
  face crops are held in memory for the result screen and dropped on Save or Start over. The
  saved enrollment lives in Application Support, excluded from backup. If a picked photo is
  only in iCloud, Photos downloads the original first, so enroll on land.
- **CLI:** writes `snapcount/Enrollment/enrollment.json` (gitignored). Delete the photos in
  `ReferencePhotos/` once enrollment is verified. The CLI file is not loaded by the app; the
  phone enrolls itself.

If no threshold reaches 98% precision, the set is not discriminative: add clearer, more
varied photos of her and check the other-children set does not include her.
