# Setup and Developer Mode

## Version requirements

For the current SDK (**DAT 0.9.0**):
- Meta AI app: **V282**
- Glasses firmware: **V125 to V126** depending on model

Absolute floors per device (pins you to older DAT versions, not recommended):

| Device | Min firmware | DAT version |
|---|---|---|
| Ray-Ban Meta | V20 | 0.3.0 |
| Ray-Ban Display | V21 | 0.4.0 |
| Oakley Meta HSTN | V20 | 0.3.0 |
| Oakley Meta Vanguard | V22 | 0.4.0 |

Meta AI app baseline for DAT 0.3.0 was V249 (both platforms).

Version mismatch is the most common cause of the SDK silently refusing to register. Check first.

## Checking glasses firmware

Meta AI app > **Devices** tab (glasses icon) > select device > **gear icon** > **Device settings** >
**General** > **About** > **Version**.

If behind: leave glasses in the case, charging, near the phone. Updates apply in the background and
are slow.

## Enabling Developer Mode  [DONE 2026-09-03]

The toggle is **not** in the glasses settings. It is in the Meta AI app's own app settings, hidden
behind a tap gesture.

1. Open the Meta AI app
2. **Settings** > **App Info**
   (App settings, reached from the top-left hamburger menu, Settings at the bottom.
   NOT the per-device settings used for the firmware check above.)
3. Tap the **app version number five times**
4. A **Developer Mode** toggle appears. Switch it on.
5. Confirm with **Enable**

Identical on iOS and Android.

### Verifying

**Meta AI settings** > **App connections** should now show a **Developer mode apps** section. Empty
until an app registers, but its existence confirms Developer Mode is live.

## Wearables Developer Center  [NOT DONE]

Separate from the phone setup. https://wearables.developer.meta.com/

1. Sign up
2. **Create an organization.** Meta's guidance is one account per org, then invite members.
   Worth doing even solo rather than working account-only.
3. Create a **Project**. This issues `MetaAppID` and `ClientToken`, and is where device permissions
   are declared.

Developer Center is also where release channels and team members are managed.

## Troubleshooting

**Toggle doesn't appear after five taps.** Taps must land on the version number and register as
distinct taps, not a fast blur. Back out of App Info and retry deliberately.

**App never shows under Developer mode apps.** Check in order: Developer Mode enabled, glasses
actively connected to the Meta AI app, `MetaAppID` / `ClientToken` matching the Developer Center
project exactly.

**Worked yesterday, broken today.** Only one third-party app can hold a Developer Mode registration
at a time. A second project against the same glasses kicks the first out.

**Permission prompt never fires.** Registration does not grant camera or mic. If no prompt appears,
the permission is probably not declared on the Developer Center project.
