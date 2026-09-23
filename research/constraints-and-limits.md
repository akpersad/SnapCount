# Constraints, Limits, and Gotchas

## The big one: publishing is closed

Everything is in **Developer Preview**. Distribution to end users is not permitted on either path.

- Native path: users must be in an **invite-only release channel**. Release channels are not open
  during preview.
- Web Apps path: password-protected URL, roughly **100 testers** cap.

The App Store is not the blocker. Meta's distribution layer is. Anything built now is a prototype
or a land-grab on a design pattern, not a shippable product.

No monetization details published at all.

## Regional gate

Full capabilities require being in an "AI glasses supported country." Developers worldwide can
download SDKs and read docs, but only those in supported countries get full capability.

## Neural Band gestures are fixed

No custom gestures. The entire vocabulary is:

- swipe left, right, up, down
- **index finger pinch** = enter / select
- **middle finger pinch** = cancel / back

Design has to fit a d-pad plus two buttons. That is the whole input budget.

## One registered app at a time (native path)

Only one third-party app can hold a Developer Mode registration simultaneously. Registering a
second app silently unregisters the first.

## MockDeviceKit does not simulate the display

The native path's no-hardware testing story covers device state, permissions, and media streaming,
but **not** the display. All display work requires the physical Ray-Ban Display.

Web Apps do have a real 600x600 Chrome simulator. Ironic given the chosen path.

## Physical display reality

Small, additive, positioned in the peripheral vision of **one eye**. Black is transparent.
Glanceable and contextual information works. Complex interfaces do not. This is a design constraint,
not a resolution problem.

## CONTESTED: is text input available?

Genuine conflict in Meta's own docs, unresolved:

- Web Apps **build guide** lists text input under unavailable capabilities.
- Web Apps **toolkit README** (facebookincubator/meta-wearables-webapp) describes an
  "on-glasses composer for forms and search boxes."

Possible that the toolkit README is newer, or that the composer is a system-level affordance rather
than a web API. **Verify on-device before designing around it.** Do not assume text entry exists.

## Version mismatch is the silent killer

Wrong Meta AI app or firmware version makes the SDK refuse to register with poor error signal.
Check versions before debugging anything else. See `setup-developer-mode.md`.

## Registration does not equal permission

Two separate steps on the native path. A successful registration grants nothing. Camera access
still needs a user prompt in the Meta AI app ("Allow once" vs "Allow always"), and the permission has
to be declared on the Developer Center project first. Permission-denied paths need building and
testing even in development.

## SDK maturity

DAT is at **0.9.0**. Pre-1.0, developer preview, features explicitly subject to change. API
reference is not in the repo READMEs, only on the docs site. Expect churn.
