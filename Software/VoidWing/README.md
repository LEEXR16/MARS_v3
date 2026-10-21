# VOID WING

A space shooter for MARS, made in Godot 4.7.2. You fly the Ranger, the ship from *Interstellar*, through the debris belt around Gargantua. The mission is to destroy a frigate's six defence turrets, then its reactor core.

The arm in the robot steers. Lifting the lever climbs and dives, sweeping the hand turns, and reaching out goes faster. Shooting is automatic: the guns fire on a target in the sights, and a missile launches once the target has been held steady. The flight model is horizon-locked for comfort: the camera never rolls, and climbing is limited to ±55°.

## Where it runs

| | Arm input | Session logs |
|---|---|---|
| **Laptop:** `VoidWing.bat` (portable Godot at `D:\SOFTWARE\Godot`), or the MARS GUI's **Launch game** | UDP JSON from the MARS GUI on 127.0.0.1:5005 | `logs/sessions.csv` and `logs/session_<time>.csv` here (never committed) |
| **Tablet:** the MARS app's **GAME**, which runs a three.js version of this game (`Software/MARS_App/assets/web/game/`), not a Godot export | `window.marsInput`, set by the app from the robot's Bluetooth data | sent to the app, which saves them in `MARS/game/` on the tablet |

Both read the same JSON: `{"t", "th1".."th4", "cuff_mm": [x, y, z], "mode", "enc_ok"}`. On the tablet it also carries a `seq` number. Both write the same session files.

**The tablet version is separate code.** Godot's web export showed its boot screen, weighed 40 MB and could only use the Compatibility renderer, so the tablet now runs its own three.js port. The two share their numbers (the DIFF table, speeds, damage, the arena, the arm mapping) but not their code. A rule changed here has to be changed in `MARS_App/assets/web/game/js/` too. The web code paths still in these scripts (`OS.has_feature("web")`) are left over from the old export.

**Logs are therapy data.** `logs/` is ignored by git and holds a `.gdignore`. Without it, Godot would import the CSVs as translations.

## Checking the look without playing

`--` options after the Godot command: `shot=<png> frames=<n,..> state=menu|play|calib|end auto input=robot cam=x,y,z`. Example: `... --path . -- shot=C:/tmp/p.png frames=60,600 state=play auto`. Test runs never write logs.
