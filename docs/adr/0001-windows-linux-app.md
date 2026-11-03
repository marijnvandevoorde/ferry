# ADR 0001: How to build the Windows and Linux app

**Status:** Accepted
**Date:** 2026-11-02
**Issue:** #35

## Context

The Mac app is SwiftUI on top of FerryKit, a Swift implementation of Fuji's Wi-Fi protocol and PC AutoSave.
FerryKit and `ferryctl` already build and pass their tests on Linux. The protocol is the risky part of the
project: it was reverse-engineered and has to be checked against the emulator and real cameras.

The Windows and Linux app needs: auto-connect, a gallery with thumbnails, import to folders and app hand-offs,
a tray icon, start at login, notifications, and signed packages (winget/MSI and the Microsoft Store, Flathub,
AppImage). It should feel at home on each platform, and stay small: this is an importer, not a photo manager.

## Options

| | A. Swift UI everywhere | B. Tauri + Rust port | C. Tauri + Swift core as a sidecar | D. Avalonia (.NET) or Flutter + port |
|---|---|---|---|---|
| Protocol implementations | 1 | 2 | 1 | 2 |
| GUI maturity on Windows/Linux | Low (SwiftCrossUI, swift-winrt) | High | High | High |
| Installers, signing, stores | Do it yourself | Built in (MSI/NSIS, AppImage, deb, Flatpak via manifest) | Built in | Good |
| Tray, autostart, notifications | Do it yourself | Plugins | Plugins | Partly |
| Contributor pool | Small | Large (web + Rust) | Large for UI | Medium |
| New risk | GUI toolkit | Keeping two protocol ports in sync | Swift on Windows; stdio protocol | Keeping two ports in sync |

## Decision

**C: a Tauri app whose UI talks to `ferryctl` running as a sidecar process.**

- `ferryctl` gets a `serve` mode that speaks JSON lines over stdin/stdout: camera status, the photo list,
  thumbnails (as files in a cache folder), import progress, and commands (connect, import, cancel).
- The Tauri shell (TypeScript UI, minimal Rust) handles windows, tray, autostart, notifications, folder
  pickers, packaging and signing.
- FerryKit stays the only protocol implementation, so the emulator tests and real-camera fixes apply to every
  platform.

This needs FerryKit on Windows (#30). Linux already works; `--static-swift-stdlib` gives a self-contained binary.

## Consequences

- #30 (FerryKit on Windows) becomes a prerequisite of the Windows app.
- The Swift runtime DLLs ship with the Windows app (around 30–50 MB). Acceptable for a desktop app.
- The JSON protocol between `ferryctl serve` and the UI gets its own tests, independent of the GUI.
- **Fallback:** if Swift on Windows turns out to be too fragile, port the protocol to Rust inside the same
  Tauri app (option B). The UI and the JSON message shapes stay the same, so little is lost.
- The Mac app stays native SwiftUI. A Tauri build for macOS is possible but not planned.
