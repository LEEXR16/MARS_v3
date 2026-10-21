# MARS tablet app: update log

Every update of the tablet app, newest first. Times are India Standard Time (IST, UTC+5:30).

- **Released** is when the version went up on [the Releases](https://github.com/LEEXR16/MARS_v3/releases) and tablets could install it with **Check for updates**.
- **Changed** is the commit time in this repository.

When you make an update, add a section at the top with the version, build, date, time and what changed.

---

## 1.2.0 (build 6): 2026-10-21

- **Changed:** 2026-10-21
- **Released:** 2026-10-21, from the laptop with `tools/publish_release.ps1` (release `v1.2.0-b6`)

- **New 3D model:** the desktop GUI's 3D view (`view3d.py`) as a solid robot, with the same kinematics. It shows the plane turning with θ1, the links, the cuff that closes and changes colour with its state, the stylised arm, and the GUI's cuff HUD. The CAD model is gone from the app.
- **VOID WING rebuilt for the tablet in three.js:** the same game and rules, without the Godot boot screen and its 40 MB engine. The new graphics:
  - The Gargantua sky is baked once.
  - Bloom on engines, lasers and explosions.
  - Smooth asteroids.
  - The resolution adapts to hold the frame rate.
- **Big touch screens** in the game, a **TOUCH** mode to try it without the robot, and a pause button.
- **Session logs are kept on EXIT and Back:** a running session is ended and saved first.
- **The APK is 51.5 MB**, down from 62.8 MB.

## 1.1.2 (build 5): 2026-10-21

- **Changed:** 2026-10-21
- **Released:** 2026-10-21, from the laptop with `tools/publish_release.ps1` (release `v1.1.2-b5`)

**A smoother update:**
- **Signing:** releases are signed with an explicitly named keystore. 1.0.0, built on GitHub, had been signed with a key Gradle made itself, so tablets refused 1.1.x with "App not installed". Tablets with 1.0.0 need to uninstall and reinstall once.
- **Both release paths** now check the finished APK's signature and refuse to publish one with another key.
- **The app** checks the update's key before opening the installer, and explains instead of failing.
- **"Install unknown apps":** the app asks for it itself, once, with a button to the setting, and the update continues by itself on return.

## 1.1.1 (build 4): 2026-10-21

- **Changed:** 2026-10-21
- **Released:** 2026-10-21, from the laptop with `tools/publish_release.ps1` (release `v1.1.1-b4`)

- **New app icon:** the MARS lever on Mars, in its 60–120° window. It replaces Flutter's default and is an adaptive icon on Android 8+. It was drawn by `tools/make_icon.py`.

## 1.1.0 (build 3): 2026-10-21

- **Changed:** 2026-10-21
- **Released:** 2026-10-21, from the laptop with `tools/publish_release.ps1` (release `v1.1.0-b3`). The robot CAD is private, so this build was made where the model is present.

- **Live 3D model:** the robot card on the MARS tab shows the robot in 3D, moving with the live joint angles. The icon in the card header switches back to 2D.
- **VOID WING game:** the Godot web export, full screen, from the **GAME** button on the MARS tab or the card on the welcome screen. The arm steers through Bluetooth. EXIT and HOLD stay on screen. Session logs are saved in `MARS/game/`.
- Web pages are served from inside the app on 127.0.0.1, with no internet access.

## 1.0.0 (build 2): 2026-10-21

- **Changed:** 2026-10-21 15:55
- **Released:** 2026-10-21 16:01, by GitHub Actions from tag `app-v1.0.0` (release `v1.0.0-b2`)

First version, built like the DYNABO app:
- **Bluetooth LE** to the robot's FSC-BT986 (needs `Firmware_SOLO_v2`).
- **Welcome screen:** version and Check for updates.
- **MARS tab:** the machine interface, with readouts, the robot view, the θ1 and torque plots, HOLD, and the CONTROL / ASSIST / SETUP pages.
- **Window mode:** 60–120°.
- **Set home:** with confirmations.
- **Load-cell platform and COP.**
- **CSV recording.**
- **Safety:** HOLD on background, a PING heartbeat, and HOLD ALL / Esc.
