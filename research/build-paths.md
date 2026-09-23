# The Two Build Paths

Meta offers two unrelated ways to build for its AI glasses. They are not tiers of the same thing.

## Device Access Toolkit (DAT) - CHOSEN PATH

A **mobile SDK**. Code lives in an iOS or Android app that runs on the phone. The glasses act as a
peripheral: camera in, audio in/out, display out.

Important clarification: "extend an existing app" in Meta's marketing does NOT mean an App Store
published app. A brand new Xcode project works. See `device-access-toolkit.md`.

## Web Apps

Standard HTML/CSS/JS hosted on a public HTTPS URL, loaded and rendered **on the glasses themselves**.
No phone app of your own involved. Ray-Ban Display only.

## Comparison

| | Web Apps | Device Access Toolkit |
|---|---|---|
| Runs on | Glasses | Phone app, glasses as peripheral |
| Languages | HTML/CSS/JS | Swift (iOS), Kotlin (Android) |
| Device support | Ray-Ban Display only | Display, Ray-Ban Meta Gen 1/2, Optics, Oakley HSTN, Oakley Vanguard |
| Camera | No | Yes (stream + photo capture) |
| Microphone / audio | No | **Unverified** - see device-access-toolkit.md |
| Display output | Yes (600x600 viewport) | Yes (UI component set) on Display models |
| Motion / orientation | Yes (DeviceMotion/DeviceOrientation) | TBC |
| GPS | Yes (relayed from phone) | Via phone app natively |
| Local iteration speed | Fast: edit, deploy, reload URL | Slower: Xcode rebuild |
| No-hardware testing | Chrome simulator (600x600) | MockDeviceKit, but does NOT simulate display |
| Distribution today | Password-protected URL, ~100 testers | Invite-only release channels |

## Why native was chosen

Camera and mic are the deciding factor, plus broader device coverage. Trade-off accepted: slower
iteration loop and no display simulation without the physical glasses.
