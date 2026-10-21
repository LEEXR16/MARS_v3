# MARS v3.1

Firmware and tablet app of **MARS** (Motorised Arm-support Robot System). It is a motorised lever, a CubeMars AK10-9 V3 in MIT mode, that supports a person's arm in a plane between 0 and 120°. Three joint encoders follow the arm, and a four-cell load platform measures weight and centre of pressure.

```
Firmware/
  Firmware_SOLO_v1/   one Teensy 4.1 runs everything (motor, encoders, load cells, solenoids), USB only
  Firmware_SOLO_v2/   SOLO_v1 + Bluetooth: FSC-BT986 on Serial5, the same lines as USB
Software/
  MARS_App/           Android tablet app (Flutter): the machine interface over Bluetooth
.github/workflows/
  release-app.yml     builds the app and publishes it as a Release (tag app-v<version>)
```

## Firmware

Open the `.ino` in Arduino IDE 2 with Teensyduino and select **Teensy 4.1**. Every library it uses comes with Teensyduino: FlexCAN_T4, EEPROM, SPI and Wire. The header comment of each sketch lists the pins, the text protocol and the commands.

- **Zero is never taken at boot:** run `HOME` once, with every link hanging straight down. The offsets are stored in EEPROM.
- **Any fault holds the lever where it is.** The spring and the solenoid brake handle power loss.
- **Bluetooth (v2):** the module's TX goes to pin 21, which is 3.3 V only. Use a divider if the module board drives its UART at 5 V.

## Tablet app

Install it from [Releases](https://github.com/LEEXR16/MARS_v3/releases): download `app-release.apk` on the tablet and open it. After that, the app's **Check for updates** button installs new versions. To build it, publish it and see what it shows, read [Software/MARS_App/README.md](Software/MARS_App/README.md).
