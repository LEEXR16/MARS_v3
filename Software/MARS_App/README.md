# MARS tablet app (Android)

The tablet version of the MARS desktop GUI's machine interface, built the same way as the DYNABO tablet app.

- **Welcome screen:** a **Machine interface** card showing whether the robot is connected. Tap it to open the MARS tab. Inside, the house icon or Android **Back** returns to the welcome screen. The connection and any recording carry on while you are there.
- **Bluetooth:** it uses **BLE** through the **FSC-BT986** module on the robot's Teensy (Serial5, pins 20 / 21). This is the same module as DYNABO, with service FFF0, notify FFF1 and write FFF2. No module settings need to change. It needs `Firmware_SOLO_v2` on the Teensy.
- **Protocol:** the Bluetooth link carries exactly the robot's USB lines (`D`, `M`, `L`, `P`, `I` and commands such as `EN`, `GO 90`, `WINDOW`). The laptop GUI can use Bluetooth too (`BLE …` entries in its port list).
- **Game and 3D model:** the **GAME** card (and the GAME button in the MARS tab) runs VOID WING. The robot card shows the live **3D model**. Both are web pages in a WebView: see **Game** and **3D model** below.
- **Screen:** landscape only. It is laid out for tablets of about 1280 × 800 dp; from about 1024 dp wide, the side columns get narrower.

## Build and install

You need Flutter at `C:\dev\flutter` and the Android SDK. Run these in PowerShell from this folder:

```powershell
$env:PATH = "C:\dev\flutter\bin;$env:PATH"
$env:JAVA_TOOL_OPTIONS = "-Djava.net.preferIPv4Stack=true"   # on this laptop Java downloads time out over IPv6
flutter build apk --release
```

The APK is written to `build\app\outputs\flutter-apk\app-release.apk` and is signed with this laptop's debug key. If Windows Smart App Control blocks the release compiler (it did for DYNABO), build in the cloud instead: see **Updates** below. `flutter build apk --debug` or `flutter run` still work on the laptop.

Two build settings in `android/` are copied from DYNABO on purpose:
- `build.gradle.kts` compiles every plugin against API 36. flutter_blue_plus 1.34 asks for API 33, and its AndroidX dependencies don't build against that.
- `gradle.properties` has `kotlin.incremental=false`, because Kotlin's incremental caches fail when the project (on `I:`) and the pub cache (on `C:`) are on different drives.

To install the APK, either:
- copy it to the tablet and open it (allow "install unknown apps"), or
- with USB debugging on, run `adb install -r build\app\outputs\flutter-apk\app-release.apk`.

The first time you connect, Android asks for the **Nearby devices** permission. On Android 11 and older it asks for **Location** instead, because BLE scanning needs it there.

## Updates over the internet

Every version is listed in [UPDATES.md](UPDATES.md). Add a section there with each update.

The welcome screen shows the app's version and a **Check for updates** button. Updates come from the **Releases** of this repository, [LEEXR16/MARS_v3](https://github.com/LEEXR16/MARS_v3/releases) (the `updateRepo` constant in `lib/core/updater.dart`). Each release holds `app-release.apk` and `version.json`.

**On the tablet:** tap **Check for updates**. If there's a newer version, tap **Download and install**. The app checks the download's size and checksum, then Android's installer opens. The robot must be disconnected first, because installing closes the app.

**Publishing a new version**, either:
- **In the cloud** (`.github/workflows/release-app.yml` at the repo root): push a tag `app-v<version>`, whose message is the notes:
  ```
  git tag -a app-v1.0.0 -m "What changed"
  git push origin app-v1.0.0
  ```
  The workflow publishes with its own token. It needs one secret, `SIGNING_KEYSTORE_B64`: the signing key as base64.
- **From the laptop:** `.\tools\publish_release.ps1 -Notes "What changed"`. It raises the build number, builds, writes `release\<tag>\` (APK + `version.json`) and uploads them with `gh`. The `release\` folder is a local build folder: it is not committed (an APK is about 50 MB), the Releases hold the files.

**Keep the signing key.** Android only installs an update signed with the same key as the installed app. Releases are signed with this laptop's debug key (`%USERPROFILE%\.android\debug.keystore`), the same key as DYNABO's. **This repository is public: never commit the key.** The cloud build reads it from the `SIGNING_KEYSTORE_B64` secret; backups are on the laptop and in DYNABO's private repository. Uninstalling the app to change the key deletes its recordings.

## MARS tab

| Area | What it shows |
|---|---|
| **Header** | <ul><li>Bluetooth connection</li><li>stream rate</li><li>mode (and CAL in progress)</li><li>faults</li><li>brake</li><li>home set or not</li></ul> |
| **Left** | <ul><li>**Motor θ1:** angle, target, speed, torque, feedforward, current, temperature, stiffness, α</li><li>**Encoders:** E1–E3 with green (OK), gold (magnet gap) or red (no reading) dots, and the raw counts</li><li>**Solenoids & power:** brake, motor power, config / left / right, height</li><li>**Load cells:** kg per cell, total, and the COP on the platform with a trail</li></ul> |
| **Centre** | <ul><li>**Robot:** the live **3D model**, or (switch with the icon in the card header) the lever dial (θ1, the 60–120° window, the target) and the arm in the robot's plane (θ2–θ4, start pose dashed)</li><li>**Lever angle θ1** and **Torque** plots (measured and target / feedforward)</li></ul> |
| **Right** | <ul><li>**HOLD** (always there)</li><li>**CONTROL:** Enable / Disable, Go to, **Start window 60–120°**, brake, solenoids, height (hold to move)</li><li>**ASSIST:** robot model, Arm attached / removed, support α, Start assist / Stop → hold</li><li>**SETUP:** clear fault, **Set home…**, measure lever, tare load cells, window spring, recording, raw command</li><li>the robot's messages</li></ul> |

- **The firmware decides:** every safety rule is in `Firmware_SOLO_v2`. When it refuses a command, its reason appears as a warning. The app only greys out what can't work right now (for example, Enable while the brake is on).
- **Brake release asks first:** with the motor off, releasing the brake leaves the lever unsupported until **Enable**. The app asks before it sends that.
- **Sliders** (Go to, α, window spring) send the value where the finger stops, not every step.
- **Height** moves only while the button is held. It repeats every 150 ms, and the firmware stops after 400 ms without a repeat.

## 3D model

`assets/web/robot3d/` is the desktop GUI's 3D view (`MARS_GUI/view3d.py`) as a solid model. It uses the same geometry, frames and behaviour as the GUI's `kinematics.py`.
- **Robot:** the column, load platform and AK10-9 motor are fixed. The robot plane turns about the motor shaft by θ1. The links (480 mm and 300 mm) turn about the plane's normal by θ2–θ4.
- **Cuff:** the gap closes when the arm is locked. The colour is amber for open, gold for measuring (it pulses) and green for locked.
- **Arm and HUD:** the stylised human arm uses the same two-link IK as the GUI and fades in once the arm is cuffed. The text in the top left is the GUI's HUD: the cuff position in mm and the cuff state.
- **No data:** it shows the start pose, as the GUI does.
- **Engine:** three.js r169 in `assets/web/lib/`, bundled with the app, so it works offline.
- **Data:** the app sets `window.marsState = {live, theta1, enc, encOk, mode, cal, armOk}` 10 times a second. The page eases the joints towards it.
- **Controls:** drag to turn the view, pinch to zoom.
- **Checking it on a PC:** serve `assets/web/` (for example `python -m http.server`) and open `robot3d/index.html?demo`, `?zero` (start pose), or `?pose=θ1,θ2,θ3,θ4&state=open|measuring|cuffed|assist`.

## Game

VOID WING, written in three.js for the tablet (`assets/web/game/`) and shown full screen in a WebView, as DYNABO runs its game. It is the same game as the laptop's Godot version (`Software/VoidWing`): the same rules, numbers, arm mapping, calibration and session files. It is built for a tablet's GPU.
- **Graphics:** the Gargantua sky is rendered once into a cubemap. Asteroids are instanced, and each ship's parts are merged per material. Engines, lasers, fire and the reactor bloom at half resolution. The drawing resolution drops by itself (down to 60 %) if frames get slow.
- **No splash:** there is no engine to load, so the game opens straight onto its start screen.
- **Input:** the app sets `window.marsInput` from every telemetry line: the desktop GUI's UDP JSON (θ1–θ4, cuff position from the same kinematics, mode, encoders OK) plus `seq`. **TOUCH** mode steers by dragging, for trying it without the robot.
- **Calibration:** the game calibrates the arm itself, as on the laptop. The calibration and settings are kept in the page's storage on the tablet, which is why the local server keeps a fixed port.
- **Session logs:** the game posts them to the app, which saves `sessions.csv` and `session_<time>.csv` in `Android/data/com.mars.mars_app/files/MARS/game/`. **EXIT** and Back end a running session first, so it is saved.
- **The robot:** the game never commands it. **EXIT** and **HOLD** stay on screen, and the app's background-HOLD rule still applies.
- **Checking it on a PC:** serve `assets/web/` and open `game/index.html`. Add `?state=play&auto&input=touch` for an autopilot session, or `&input=robot&feed` for a fake arm. Test runs started with `state=` send no logs.

**Local server:** both pages are ES modules, and Android's WebView blocks module imports for `file://` pages. `lib/core/asset_server.dart` serves `assets/web/` on `127.0.0.1` only, on port 47811 when it is free. Only this device can reach it, and `res/xml/network_security_config.xml` allows plain HTTP to 127.0.0.1 alone.

## Safety

- **HOLD ALL** (top right, also on the welcome screen) puts the robot on HOLD. A hardware keyboard's **Esc** does the same.
- **Leaving the app holds the robot.** When the app goes to the background (home button, another app, screen off), HOLD is sent. A message says so when you come back.
- **Heartbeat:** the app sends `PING` every 200 ms. If the app dies or Bluetooth drops, the firmware faults (GUI LINK) and holds after 1 s. The brake still covers power loss.
- **Two controllers:** the laptop (USB or Bluetooth) and the tablet can be connected at the same time, and both can command the robot. Agree who is driving.
- **Screen:** it stays on while the robot is connected.

## Recordings

**SETUP → Record** saves every telemetry line (25 per second over Bluetooth) to `Android/data/com.mars.mars_app/files/MARS/session/MARS_<date>_<time>.csv`. The columns are app time, the D-line fields, and kg1–kg4. Connect the tablet to a PC over USB (File transfer) to copy the files off.

## Layout

```
lib/
  main.dart               app shell: welcome screen, tab bar, HOLD ALL, Esc, background hold, wakelock, messages
  core/
    ble.dart              scan + transport (FSC-BT986, FFF0/FFF1/FFF2), flutter_blue_plus   (from DYNABO)
    line_device.dart      base device: connect, PING heartbeat, ordered writes, line framing
    recorder.dart         CSV recording                                                     (from DYNABO)
    asset_server.dart     serves assets/web/ to the WebViews on 127.0.0.1
    updater.dart          updates from GitHub Releases: check, download, open the installer (from DYNABO)
  devices/mars/
    mars_protocol.dart    D / M / L / P lines, fault and relay bits, COP (= the MARS GUI's)
    mars_device.dart      MARS commands and the latest state
    mars_model.dart       history for the plots, stream rate, COP trail, recording
  ui/
    theme.dart            the Mars palette (= the MARS desktop GUI's theme.py)
    widgets.dart          cards, status pills, slider rows, value rows                     (from DYNABO)
    plots.dart            time plot, load-cell platform (CustomPainter)
    robot_view.dart       lever dial and arm plane (CustomPainter)
    connect_dialog.dart   BLE device picker, device header                                 (from DYNABO)
    web_page.dart         a bundled web page in a WebView, with a message bridge
    game_screen.dart      VOID WING full screen: arm input in, session logs out, EXIT / HOLD
    update_dialog.dart    Check for updates dialog                                         (from DYNABO)
    device_tab.dart       DeviceController interface
    tabs/mars_tab.dart    the MARS interface
assets/web/
  lib/                    three.js r169 + the addons the pages use (MIT, LICENSE-three.txt)
  robot3d/                the 3D model page (scene.js: the GUI's view3d.py)
  game/                   VOID WING in three.js (js/: world, ships, actors, fx, hud, menu, input, sfx)
tools/
  publish_release.ps1     build + publish a release from the laptop
test/
  protocol_test.dart      line parsing, framing across BLE packets, and a render of both screens at 1280 × 800
```

To run the tests, use `flutter test`.

## Not in this version

- **Calibration wizard and τg sweep:** these stay in the desktop GUI. The tablet shows the result (robot model) and can measure the lever and the arm.
