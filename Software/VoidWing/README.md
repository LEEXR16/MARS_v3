# VOID WING

A space shooter for MARS, made in Godot 4.7.2. You fly the Ranger, the ship from *Interstellar*, through the debris belt around Gargantua. The mission is to destroy a frigate's six defence turrets, then its reactor core.

The arm in the robot steers. Lifting the lever climbs and dives, sweeping the hand turns, and reaching out goes faster. Shooting is automatic: the guns fire on a target in the sights, and a missile launches once the target has been held steady. The flight model is horizon-locked for comfort: the camera never rolls, and climbing is limited to ±55°.

## Where it runs

| | Arm input | Session logs |
|---|---|---|
| **Laptop:** `VoidWing.bat` (portable Godot at `D:\SOFTWARE\Godot`), or the MARS GUI's **Launch game** | UDP JSON from the MARS GUI on 127.0.0.1:5005 | `logs/sessions.csv` and `logs/session_<time>.csv` here (never committed) |
| **Tablet:** the web export, inside the MARS app (**GAME**) | `window.marsInput`, set by the app from the robot's Bluetooth data | sent to the app, which saves them in `MARS/game/` on the tablet |

Both read the same JSON: `{"t", "th1".."th4", "cuff_mm": [x, y, z], "mode", "enc_ok"}`. On the tablet it also carries a `seq` number.

## Exporting for the tablet app

Export with Godot's **Web** export templates for 4.7.2. In the editor, Project → Export → **Web** → Export Project. From the command line:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" ../MARS_App/assets/web/game/index.html
```

- **Threads:** the preset (`export_presets.cfg`) builds without threads, so the page needs no special server headers.
- **Excluded files:** `logs/` and `VoidWing.bat` are left out.
- **Renderer:** the web build uses Godot's Compatibility renderer. `project.godot` turns off high-DPI rendering and screen-space AA for it, and the asteroids use a lighter mesh (`space.gd`).

**Logs are therapy data.** `logs/` is ignored by git and holds a `.gdignore`. Without it, Godot would import the CSVs as translations and pack them into an export.

## Checking the look without playing

`--` options after the Godot command: `shot=<png> frames=<n,..> state=menu|play|calib|end auto input=robot cam=x,y,z`. Example: `... --path . -- shot=C:/tmp/p.png frames=60,600 state=play auto`. Test runs never write logs.
