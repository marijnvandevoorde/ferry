# Roadmap

**Goal:** get photos off a camera without cables or card readers, into whatever the user already uses.
Not a Lightroom replacement: no editing, no catalog, no ratings, no remote shooting.
See the [round table](docs/roundtable.md) for the reasoning.

Each step is a small GitHub issue, grouped into [milestones](https://github.com/marijnvandevoorde/ferry/milestones).
The order below is the order of work.

## ✅ v0.1: X-T20 to Apple Photos

- Fuji Wi-Fi protocol (PTP over TCP) in Swift
- Mac app: auto-detect, gallery, import new or selected photos to Apple Photos, remember what was imported
- Works with a VPN on (binds to the Wi-Fi interface)

## v0.2: All Fuji Wi-Fi cameras

Fuji cameras from roughly 2014 to 2021 that work with *Camera Remote* over Wi-Fi.

- Detect the camera's protocol generation from its version properties
- Cameras without remote mode (X-A2, X30, X-E2 era)
- "Send selected images" started from the camera (multiple-transfer mode)
- Test every model the vcam emulator knows: X-A2, X30, X-F10, X-T2, X-T4, X-T30, X-S10, X-H1, GFX100 II
- Warn when the camera sends reduced-size JPEGs
- Camera-specific instructions in the app
- Compatibility table and a camera test report template
- CI: build and unit tests

## v0.3: Mac app polish

- Destinations: Apple Photos, or a folder with a date template
- Hand-off to Lightroom Classic (auto-import folder) and Capture One (hot folder)
- Optional backup copy to a second folder
- Menu bar mode, notifications, launch at login
- Keep the Mac awake during an import, resume after a dropped connection
- Quick Look preview, skip videos, optional filename template
- Rejoin the previous Wi-Fi network after an import
- Sandboxed, so it can ship in the Mac App Store
- Signed and notarized DMG, Mac App Store submission, Homebrew cask

## v0.4: Import over home Wi-Fi

Fuji's *PC AutoSave* lets the camera join your home network and send photos to the computer. The Mac stays online.

- Register the computer with the camera
- Receive photos when the camera connects
- Pairing UI in the app

## v0.5: Portable core

- FerryKit builds on Linux and Windows
- `ferryctl import` and `ferryctl watch`: import new photos into a folder from the command line, or automatically when the camera appears
- CI on Linux and Windows, protocol tests against the emulator

## v1.0: Windows and Linux app

- Decide the GUI technology (architecture decision record)
- Windows and Linux app: connect, gallery, import
- Destinations: Pictures folder (Windows Photos), Lightroom Classic, Photoshop Elements watched folders,
  digiKam, darktable, Shotwell, Immich
- Tray icon, start at login
- Signed packages: MSIX/MSI on winget and the Microsoft Store, Flathub, signed AppImage

## Later: newer Fuji cameras

Cameras from about 2022 onwards (X-T5, X-S20, X100VI, …) pair over Bluetooth and then switch to Wi-Fi.

- Research the Bluetooth hand-off (needs testers with hardware)
- The newer gallery protocol
- Bluetooth pairing on macOS

## Later: other brands

Brands whose Wi-Fi transfer only works with a phone app.

- Camera driver abstraction
- Olympus / OM System, Ricoh GR, Sony (older "Send to Smartphone"), Panasonic Lumix, Canon and Nikon (PTP/IP)

## Signing and stores

Every release is signed: Developer ID plus notarization and the App Store on macOS, a code-signing
certificate and the Microsoft Store on Windows, Flathub on Linux. Signing keys live in GitHub secrets,
never in the repository.

## Out of scope

Editing, catalogs, ratings and culling, remote shooting and liveview, deleting from the camera, accounts,
cloud, telemetry, firmware updates.
