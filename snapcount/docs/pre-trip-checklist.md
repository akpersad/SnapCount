# Pre-trip checklist

Everything here runs on the real iPhone and glasses. Do sections 1 and 2 **on land with good
Wi-Fi**: registration cannot happen at sea. Tick items off in `WORKPLAN.md` Phase 7 as they pass.

Rebuild and install first (`xcodegen generate --spec snapcount/project.yml`, then run from Xcode
on the phone).

## 1. Register and connect (Phase 5a to 5c)

1. Glasses on, charged, paired in the Meta AI app, Developer Mode still on.
2. SnapCount: **Connect SnapCount to Meta AI**. The Meta AI app opens. Approve. It should bounce
   back to SnapCount and the button should be replaced by **Start Glasses Session**.
   - If it lands in Meta AI and never returns, the `snapcount://` URL scheme is mismatched.
     See `info-plist.md`.
3. **Start Glasses Session**. The first time, the Meta AI app asks for camera permission.
   Approve. Status should reach **Connected, count on display**.
4. **Denied path (5b):** revoke camera access for SnapCount in the Meta AI app, start a session
   again, and confirm SnapCount shows the "Camera access was declined" message rather than
   hanging. Re-allow it afterwards.

## 2. Capture and count (5d, 6)

1. **On the glasses display** you should see the count, "photos of <name> today", and a
   **Take photo** button.
2. Look at her and tap **Take photo** on the glasses. Within a few seconds:
   - the glasses show "Taking photo…", then the count goes up by one;
   - the phone shows **Last photo** with a time and pixel size.
3. **Write down the pixel size.** If it is small (under about 1000 px on the short edge), faces
   more than a few feet away will be too small to recognize, and the stream resolution needs
   raising in `GlassesController`.
4. Take one of something else. Only the phone's total should move, not the count.
5. Take a phone photo of her. The glasses count should go up too (6c: the HUD follows the
   library count).
6. **Pocket test:** lock the phone, put it away, tap **Take photo** on the glasses. Does it
   still work? If not, note it: it means the app only captures while in the foreground.

## 3. Airplane mode, end to end (Phase 7)

The single most important test. It proves both "nothing leaves the phone" and "works at sea".

1. Airplane mode **on** on the phone. Turn Wi-Fi and Bluetooth back **on** (the glasses need
   them; neither reaches the internet on its own).
2. Force-quit SnapCount and reopen it.
3. Repeat section 2, steps 2 to 5. Everything must work.
4. If a session will not start in airplane mode, that is a trip blocker. Report the exact
   message shown.

## 4. No network egress (Phase 7)

The simplest reliable check needs no proxy.

1. Settings, Privacy & Security, **App Privacy Report**: turn it on.
2. Use SnapCount normally for a while with internet available: a glasses session, a few
   captures, a few phone photos.
3. Open App Privacy Report, find **SnapCount**, and look at **Network Activity** and
   **Website Activity**.
4. **Pass:** nothing listed, or only domains you can account for. Anything with `facebook`,
   `meta`, `fbcdn`, `graph`, or an analytics name in it is a **fail** (the opt-outs are not
   working). Screenshot it and stop.

Registration itself (section 1) may legitimately touch the network. Registration happens inside
the Meta AI app, so it should be listed under Meta AI, not SnapCount.

## 5. Storage (Phase 7)

SnapCount, **Privacy Check**. Every row should be green on the phone:
- analytics and crash reporting off
- face data, photo results, and glasses photos all excluded from backups
- face data "Unreadable while the phone is locked"

(The last row fails in the simulator, which does not enforce file protection. Only the phone's
answer counts.)

## 6. Battery (Phase 7)

1. Charge glasses and phone to 100%.
2. Keep a glasses session running for 2 hours, taking a photo roughly every 10 minutes.
3. Note both battery levels. The camera only runs for a few seconds per photo, so the display
   session should be the main cost.
4. If the glasses drop more than about 30% in 2 hours, end the session when not in use and
   start it again when needed.

## 7. Last things before leaving

- [ ] App Privacy Report checked (section 4)
- [ ] Airplane-mode test passed (section 3)
- [ ] Do **not** update the glasses firmware or the Meta AI app after testing. Updates can turn
      off Developer Mode, and registration cannot be redone at sea.
- [ ] Build expiry: a free-account build stops launching after 7 days, a paid account after a
      year. Check which you have, and reinstall the build the day before departure if needed.
