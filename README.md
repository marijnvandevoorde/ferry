# Fuji Import

An open-source Mac app that imports photos from Fujifilm X cameras over Wi-Fi straight into Apple Photos.
It replaces the photo-transfer part of Fujifilm's unmaintained *Camera Remote* app.

Fujifilm X and GFX cameras from roughly 2014–2021 that work with *Camera Remote* over Wi-Fi should work.
See [compatibility](#compatibility) and the [roadmap](ROADMAP.md).

## Using it

1. On the camera, press **Playback**, then choose **Wireless Communication** (Wi-Fi button, or Menu → Connection Setting).
2. On the Mac, join the camera's Wi-Fi network (`FUJIFILM-X-…`). Your Mac will be offline while connected.
3. Open Fuji Import. It finds the camera automatically; press **OK** on the camera if it asks.
4. Click **Import New**, or select photos and click **Import Selected**.

Photos go into your Photos library, in a *Fujifilm* album by default. Fuji Import remembers what it imported,
so next time only new photos are offered. Settings (⌘,) has the camera address, auto-connect, auto-import and album options.
If something goes wrong, **Window → Connection Log** shows what the camera said.

Over Wi-Fi the camera only offers JPEGs (no RAF files).

## Compatibility

| Camera | Real camera | Emulator |
|--------|-------------|----------|
| X-T20 | ✅ | ✅ |
| X-A2, X30, X-F10, X-T2, X-T4, X-T30, X-S10, X-H1, GFX100 II | not yet | ✅ |
| X-T5, X-S20, X100VI and other cameras that pair over Bluetooth | ❌ planned | |

"Emulator" means the protocol works against [vcam](https://github.com/petabyt/vcam)'s model of that camera.
Tried it with your camera? Please [file a camera report](https://github.com/marijnvandevoorde/fuji-import/issues/new?template=camera-report.yml),
whether it worked or not.

## Command line (macOS and Linux)

`fujictl` imports without the app, for example on a Linux machine or from a script:

```sh
swift build -c release --product fujictl
.build/release/fujictl import ~/Pictures/Fuji        # new photos, into Year/Date folders
.build/release/fujictl watch ~/Pictures/Fuji         # keep running; import whenever the camera's Wi-Fi is joined
.build/release/fujictl autosave register             # register with the camera's PC AutoSave
.build/release/fujictl watch --autosave ~/Pictures/Fuji   # import over the home network
```

Run `fujictl` without arguments for all commands and options (folder and file name templates, `--skip-videos`, …).

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open FujiImport.xcodeproj
```

The project is laid out as:

- `Sources/FujiKit` – Swift implementation of Fujifilm's Wi-Fi protocol (PTP over TCP, port 55740).
- `Sources/fujictl` – command-line tool for macOS and Linux (see below).
- `App` – the SwiftUI app.

### Testing without a camera

[vcam](https://github.com/petabyt/vcam) emulates Fujifilm cameras, including the X-T20:

```sh
docker build -t vcam-fuji scripts/vcam
docker run --rm -p 55740-55742:55740-55742 -v "$PWD/card:/card" vcam-fuji build/vcam fuji_x_t20 tcp --local-ip --fs /card
swift run fujictl --host 127.0.0.1 list
# point the app at it (or set the camera address in Settings)
defaults write ~/Library/Containers/io.github.fujiimport.FujiImport/Data/Library/Preferences/io.github.fujiimport.FujiImport cameraHost 127.0.0.1
```

vcam only supports one connection per run; restart it between sessions.
`scripts/test-vcam.sh` runs the download test against every emulated Fuji model, and
`scripts/test-vcam-autosave.sh` tests PC AutoSave. CI runs both on Linux.

## Credits

The protocol handling is a port of [libfuji](https://github.com/petabyt/libfuji) by Daniel Cook (MIT),
which reverse-engineered Fujifilm's apps from packet captures.

## License

MIT
