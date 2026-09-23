# Privacy Architecture

The requirement: a child's face is processed, and none of it leaves the device. This file is
the checklist that makes that structural rather than aspirational.

## Threat model

Not "is Meta evil." The realistic risks are mundane:
1. A dependency phones home without us noticing.
2. Face data ends up in an iCloud backup and therefore on Apple's servers.
3. Meta's SDK telemetry is on by default and we forget to turn it off.
4. We ship reference photos when we only needed vectors.

## Controls

### 1. No network code, verifiable

The app makes no outbound connections. This is checkable rather than promised:

```
# should return nothing
grep -rE 'URLSession|Alamofire|\.dataTask|http://|https://' Sources/
```

Add it to the build as a run-script phase so a future edit that adds networking fails loudly.

Caveat: the DAT SDK itself uses the local network for camera streaming. That is link-local
to the phone, not internet egress. The grep applies to *our* code.

### 2. Kill Meta's telemetry

In Info.plist, inside the `MWDAT` dictionary:

```xml
<key>OptOut</key>
<true/>
```

Disables analytics. Crash reporting is **on by default** and needs the same treatment.
Verify with Charles or a similar proxy before the trip, not after.

### 3. Store vectors, not faces

The enrollment set is persisted as L2-normalized 512-float embeddings. Reference photos are
used to compute those and then discarded.

An embedding is not trivially reversible to an image. It is still biometric data, so it gets
the same handling as a photo would.

### 4. Keep it out of backups

Enrollment data and the photo log live in the app container with:

```swift
var values = URLResourceValues()
values.isExcludedFromBackup = true
try url.setResourceValues(&values)
```

Prevents the biometric template syncing to iCloud.

### 5. No Photos library write-back by default

If captured photos are saved to the system Photos library they inherit iCloud Photos sync.
Default to storing them in the app container. Make library export an explicit, per-photo action.

### 6. Core ML stays on-device

Core ML inference is local by construction. Set `MLModelConfiguration.computeUnits` explicitly
and never use any cloud-backed model API.

## Pre-trip verification

Do these on land, with good Wi-Fi, before boarding.

- [ ] `OptOut = true` set and confirmed
- [ ] Crash reporting disabled and confirmed
- [ ] Proxy the app for one full capture session, confirm zero unexpected egress
- [ ] Confirm enrollment data is excluded from backup
- [ ] Confirm reference photos are deleted after enrollment
- [ ] Airplane-mode test: the full capture-to-count loop works with no internet

That last one matters twice over. It proves the privacy claim and it proves the app works
at sea.
