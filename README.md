# Ferry

An open-source app that imports photos from your camera over Wi-Fi, no cable or card reader. On the Mac
it imports straight into Apple Photos or a folder; on Windows and Linux into a folder, optionally also to Immich.

It works with Wi-Fi cameras from Canon, Fujifilm, GoPro, Olympus / OM System, Ricoh, Sony and Panasonic, by talking to
them the way their phone apps do. How well each one is tested differs.
See [compatibility](#compatibility) and the [roadmap](ROADMAP.md).

## Using it

1. On the camera, turn on Wi-Fi the way you would for its phone app.
2. On the Mac, join the camera's Wi-Fi network. Your Mac will be offline while connected.
3. Open Ferry. It finds the camera automatically; press **OK** on the camera if it asks.
4. Click **Import New**, or select photos and click **Import Selected**.

Photos go into your Photos library, in a *Ferry* album by default. Ferry remembers what it imported,
so next time only new photos are offered. Settings (⌘,) has the camera address, auto-connect, auto-import and album options.
If something goes wrong, **Window → Connection Log** shows what the camera said.

Ferry imports whatever the camera offers over Wi-Fi. Fujifilm cameras only offer JPEGs (no RAF files).
Fujifilm cameras can also join your home Wi-Fi and send photos from there (PC AutoSave), so the Mac stays online.

## Compatibility

| Camera | Real camera | Emulator |
|--------|-------------|----------|
| Fujifilm X-T20 | ✅ | ✅ |
| Fujifilm X-A2, X30, X-F10, X-T2, X-T4, X-T30, X-S10, X-H1, GFX100 II | not yet | ✅ |
| Fujifilm X-T5, X-S20, X100VI and others that pair over Bluetooth | ❌ planned | |
| Canon EOS R, 90D, 5D Mark III, Rebel SL2, Rebel T6, PowerShot G7 X III (standard PTP/IP) | not yet | ✅ |
| Olympus / OM System (OI.Share), Ricoh GR II / III | not yet | mock API only |
| GoPro HERO9 Black and later (Open GoPro) | not yet | mock API only |
| Older Sony Alpha and Panasonic Lumix with Wi-Fi sharing (DLNA) | not yet | mock API only |

"Emulator" means the protocol works against [vcam](https://github.com/petabyt/vcam)'s model of that camera.
Tried it with your camera? Please [file a camera report](https://github.com/marijnvandevoorde/ferry/issues/new?template=camera-report.yml),
whether it worked or not.

## Windows and Linux

`apps/desktop` is a Tauri app that runs `ferryctl serve` in the background: connect, browse, and import into a
folder (your Pictures folder for Windows Photos, or a folder Lightroom, Photoshop Elements, digiKam or darktable
watches), optionally also to Immich. To run it from source you need Swift, Rust and Node with pnpm:

```sh
cd apps/desktop
pnpm install
pnpm run sidecar     # builds ferryctl and puts it where Tauri expects it
pnpm tauri dev       # FERRY_HOST=127.0.0.1 points it at the emulator
```

See [importing into other photo apps](docs/other-apps.md).

## Command line (macOS, Linux, Windows)

`ferryctl` imports without the app, for example on a Linux machine or from a script:

```sh
swift build -c release --product ferryctl
.build/release/ferryctl import ~/Pictures/Fuji        # new photos, into Year/Date folders
.build/release/ferryctl watch ~/Pictures/Fuji         # keep running; import whenever the camera's Wi-Fi is joined
.build/release/ferryctl autosave register             # register with the camera's PC AutoSave
.build/release/ferryctl watch --autosave ~/Pictures/Fuji   # import over the home network
```

Run `ferryctl` without arguments for all commands and options (folder and file name templates, `--skip-videos`,
`--immich` uploads, …).

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Ferry.xcodeproj
```

The project is laid out as:

- `Sources/FerryKit` – Swift implementation of Fujifilm's Wi-Fi protocol (PTP over TCP, port 55740).
- `Sources/ferryctl` – command-line tool for macOS and Linux (see below).
- `App` – the SwiftUI app.

### Testing without a camera

[vcam](https://github.com/petabyt/vcam) emulates Fujifilm cameras, including the X-T20:

```sh
docker build -t vcam-fuji scripts/vcam
docker run --rm -p 55740-55742:55740-55742 -v "$PWD/card:/card" vcam-fuji build/vcam fuji_x_t20 tcp --local-ip --fs /card
swift run ferryctl --host 127.0.0.1 list
# point the app at it (or set the camera address in Settings)
defaults write ~/Library/Containers/io.github.fujiimport.FujiImport/Data/Library/Preferences/io.github.fujiimport.FujiImport cameraHost 127.0.0.1
```

vcam only supports one connection per run; restart it between sessions.
`scripts/test-vcam.sh` runs the download test against every emulated Fuji model, and
`scripts/test-vcam-autosave.sh` tests PC AutoSave. CI runs both on Linux.

## Website

`site/` is the marketing site (Cloudflare Pages, six languages, no JavaScript of its own). See [site/README.md](site/README.md).
The working name for the app is Ferry ([how we got there](docs/roundtable-4.md)); the site reads it from `site/site.json`.

## Credits

The protocol handling is a port of [libfuji](https://github.com/petabyt/libfuji) by Daniel Cook (MIT),
which reverse-engineered Fujifilm's apps from packet captures.

## License

MIT
