# Fuji Import

An open-source Mac app that imports photos from Fujifilm X cameras over Wi-Fi straight into Apple Photos.
It replaces the photo-transfer part of Fujifilm's unmaintained *Camera Remote* app.

Tested on a real X-T20 and on an emulated X-T20. Other Wi-Fi Fujifilm X cameras from roughly 2015–2020 that use
*Camera Remote* should work the same way.

## Using it

1. On the camera, press **Playback**, then choose **Wireless Communication** (Wi-Fi button, or Menu → Connection Setting).
2. On the Mac, join the camera's Wi-Fi network (`FUJIFILM-X-…`). Your Mac will be offline while connected.
3. Open Fuji Import. It finds the camera automatically; press **OK** on the camera if it asks.
4. Click **Import New**, or select photos and click **Import Selected**.

Photos go into your Photos library, in a *Fujifilm* album by default. Fuji Import remembers what it imported,
so next time only new photos are offered. Settings (⌘,) has the camera address, auto-connect, auto-import and album options.
If something goes wrong, **Window → Connection Log** shows what the camera said.

Over Wi-Fi the camera only offers JPEGs (no RAF files).

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open FujiImport.xcodeproj
```

The project is laid out as:

- `Sources/FujiKit` – Swift implementation of Fujifilm's Wi-Fi protocol (PTP over TCP, port 55740).
- `Sources/fujictl` – command-line tool for testing: `swift run fujictl [--host IP] info|list|download <dir>|thumbs <dir>`
- `App` – the SwiftUI app.

### Testing without a camera

[vcam](https://github.com/petabyt/vcam) emulates Fujifilm cameras, including the X-T20:

```sh
git clone https://github.com/petabyt/vcam && cd vcam
# Build in a Linux container (see vcam's Dockerfile), then:
docker run --rm -p 55740-55742:55740-55742 -v "$PWD/card:/card" <image> build/vcam fuji_x_t20 tcp --local-ip --fs /card
swift run fujictl --host 127.0.0.1 list
defaults write io.github.fujiimport.FujiImport cameraHost 127.0.0.1   # point the app at it
```

vcam only supports one connection per run; restart it between sessions.

## Credits

The protocol handling is a port of [libfuji](https://github.com/petabyt/libfuji) by Daniel Cook (MIT),
which reverse-engineered Fujifilm's apps from packet captures.

## License

MIT
