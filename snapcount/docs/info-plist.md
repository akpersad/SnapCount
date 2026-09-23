# Info.plist Reference

Complete and corrected. Paste-ready for the app target.

## The scheme mismatch to fix first

Meta's generated snippet contains **`myexampleapp://`**, which is their placeholder, not a
value derived from your project. The Universal link field in Developer Center was saved as
**`snapcount://`**.

**These must match.** Use `snapcount://` everywhere. Leaving Meta's placeholder in place means
the Meta AI app tries to call back to a scheme your app does not claim, and registration hangs
with no useful error.

## Resolved: a custom scheme is accepted

Open question 1 is closed. The Developer Center Universal link field accepted `snapcount://`,
so a real universal link with a hosted `apple-app-site-association` file is **not** required.
No domain, no Vercel, no associated-domains entitlement.

## Values that come from Secrets.xcconfig

`Secrets.xcconfig` is gitignored. Set it as the config file for the target's build
configurations, then reference the values with `$(...)` in Info.plist.

Do **not** put the URL scheme in the xcconfig: xcconfig treats `//` as a comment even mid-value,
so `snapcount://` would be silently truncated to `snapcount:`. Keep it a literal in the plist.

## The plist

```xml
<!-- Meta Wearables DAT -->
<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <string>snapcount://</string>

    <key>MetaAppID</key>
    <string>$(META_APP_ID)</string>

    <key>ClientToken</key>
    <string>$(META_CLIENT_TOKEN)</string>

    <key>TeamID</key>
    <string>$(DEVELOPMENT_TEAM)</string>

    <!-- Disables Meta analytics. Required for this project: see privacy-architecture.md.
         Crash reporting is enabled by default and must be turned off too. -->
    <key>OptOut</key>
    <true/>
</dict>

<!-- Claim the scheme Meta AI calls back on -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.akpersad.snapcount</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>snapcount</string>
        </array>
    </dict>
</array>

<!-- Required for the glasses link -->
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.meta.ar.wearable</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string>
</array>

<!-- Usage strings. These are user-facing. -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>SnapCount connects to your glasses over Bluetooth to capture photos and show your daily count.</string>

<key>NSLocalNetworkUsageDescription</key>
<string>SnapCount uses a direct local connection to your glasses to transfer photos. Photos stay on this device.</string>

<key>NSBonjourServices</key>
<array>
    <string>_bonjour._tcp</string>
</array>

<key>NSCameraUsageDescription</key>
<string>SnapCount uses the camera for testing with a simulated device.</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>SnapCount reads today's photos to count how many include the person you enrolled. Photos are analyzed on this device and never uploaded.</string>
```

Note the `CFBundleURLSchemes` entry is bare `snapcount`, without `://`. The `://` belongs only
in `AppLinkURLScheme`.

`NSPhotoLibraryUsageDescription` is needed for Phase 4 and is not in Meta's list, since it is
an Apple requirement rather than a DAT one.

## Deployment target

iOS 18 minimum. `AGENTS.md` says the SDK supports iOS 16, but `SnapCountCore` uses the modern
Swift Vision API which requires 18.
