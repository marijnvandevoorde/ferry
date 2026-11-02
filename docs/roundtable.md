# Round table: what should Fuji Import do?

> This is a simulated round table. The participants are composite personas, written to stress-test the roadmap
> from different points of view. They are not real interviews. Real feedback goes in GitHub Discussions and
> issues and wins over anything in here.

**Facilitators**

- **Noor**, UX designer
- **Sam**, product manager

**Photographers**

| Name | Level | Camera | Computer | Where photos end up |
|------|-------|--------|----------|---------------------|
| Lea | Amateur, travel and family | X-T20, X-S10 | MacBook Air | Apple Photos, iCloud |
| Bram | Amateur, parent, weekends | X100V | Windows laptop | Windows Photos, OneDrive |
| Jules | Amateur, tinkerer | X-E3, Olympus E-M10 | Linux (Fedora) | digiKam, darktable |
| Femke | Pro, weddings and events | X-H2S, X-T4 | MacBook Pro, Windows desktop | Lightroom Classic |
| Karim | Pro, documentary and travel | X-Pro3, Ricoh GR III | MacBook Pro | Capture One, two backup drives |
| Anouk | Pro, studio and product | GFX100S | Windows workstation | Capture One (tethered) |

---

## 1. How do you get photos off the camera today?

**Lea:** Card reader, when I can find it. The new MacBook has no SD slot and the dongle lives in a drawer
somewhere. Fuji's phone app works one day, not the next. Usually the photos just stay on the camera.

**Bram:** I plug the camera into the laptop with USB, and Windows asks me what to do every time. Half the time
I just close that dialog.

**Jules:** gphoto2 over USB, or I pull the card. I'd love to do it without unplugging anything.

**Femke:** For jobs, always the card, both slots, into Lightroom with a backup copy. That will not change.
What I do want wireless: during a wedding I send ten selects to the couple or the planner. Today that's the
phone app, and it's painful.

**Karim:** Card reader, into Capture One, then two backups. On the road I'd love to empty the camera in the
hotel room without fiddling with adapters.

**Anouk:** I shoot tethered over USB-C. Wireless is not for me in the studio. I'm here to tell you what not
to build.

**Sam:** So nobody wants to replace the card for bulk professional ingest. The wireless job is "get the photos
off without hardware", for casual use and quick selects on the road.

## 2. What would the perfect import look like?

**Lea:** I turn on the camera, the Mac notices, the photos land in Photos. I don't want to think about it.

**Noor:** And what if the Mac has to leave your home Wi-Fi to talk to the camera?

**Lea:** That's annoying. If it has to happen, it should switch back by itself afterwards.

**Bram:** Same. And on Windows I just want them in my Pictures folder. Windows Photos picks them up from there,
and OneDrive backs them up.

**Jules:** A folder, with a date layout I choose, like `2026/2026-11-02`. digiKam and darktable both watch
folders.

**Femke:** For Lightroom Classic, a folder that Lightroom auto-imports is enough. Don't try to talk to
Lightroom's catalog directly. Also tell me clearly when the camera has resized the JPEGs for smartphone,
because the camera does that silently.

**Karim:** For Capture One, a hot folder. And a second copy to a backup folder would be lovely: one import,
two destinations.

**Noor:** Should the app rename files?

**Karim:** Optional. Default: keep the camera's names. Renaming should be a template, off by default.

## 3. What do you want to see before importing?

**Lea:** Thumbnails, which ones are new, one big button.

**Femke:** A larger preview when I press space, like Quick Look. Select ten, send. That's all the "culling" I
need here.

**Karim:** Grouping by day is good. Show videos too, but let me skip them because they're slow over Wi-Fi.

**Noor:** Star ratings, flags, colour labels?

**Femke:** No. Rating belongs in Lightroom or Photo Mechanic. If you add ratings I won't trust this app to stay
small.

**Jules:** Agreed. Keep the selection, nothing else.

## 4. What should happen in the background?

**Lea:** A menu bar icon. When the camera shows up: notification, "12 new photos", and import if I said so.

**Bram:** Run when Windows starts, sit in the tray, done.

**Karim:** Don't let the laptop sleep during an import, and resume where you left off if the connection drops.

**Sam:** And no camera available?

**Lea:** Then the app should be invisible.

## 5. Things you do NOT want

Everyone agreed on these. They're out of scope:

- Editing, presets, filters or film simulation tweaks
- A photo library, catalog or albums manager (beyond putting photos into the app the user already uses)
- Ratings, flags, culling workflows
- Remote shooting and liveview (Fuji's apps already do this, and it isn't the job)
- Deleting photos from the camera after import (**Femke:** "never touch my card")
- Accounts, cloud, subscriptions, telemetry
- Firmware updates, GPS sync, camera settings backup

**Anouk:** Tethered shooting is a different product. Don't drift into it.

## 6. Other brands and newer Fujis

**Jules:** My Olympus has Wi-Fi too, and Olympus' desktop software never supported it. Same app for both would be great.

**Karim:** The Ricoh GR III is the same story: phone app only.

**Femke:** My X-H2S pairs over Bluetooth first. If that works on the Mac some day, great, but get the older
cameras rock-solid first.

**Sam:** Agreed. Newer Fujis and other brands come after the platforms we already promised.

## 7. Platforms

**Bram:** A real Windows app with an installer. Not a command line.

**Jules:** On Linux, a command line *and* a small app. Flatpak please.

**Femke:** Windows and Mac behaving the same matters to me. I use both.

---

## Takeaways

**The job:** get photos off the camera without cables, into whatever the user already uses, with zero thinking.

**Must have**

1. Automatic detection and connection, with clear camera-side instructions per model.
2. Import only new photos, reliably, with resume after a dropped connection.
3. Destinations: Apple Photos (macOS), a folder with a date template (all platforms), plus app hand-off:
   Lightroom Classic auto-import, Capture One hot folder, Windows Photos/Pictures, Photoshop Elements
   watched folders, digiKam, darktable, Immich.
4. Optional second copy (backup destination).
5. A background mode: menu bar or tray, notifications, auto-import.
6. Not losing internet: PC AutoSave over the home network where the camera supports it, and otherwise rejoining
   the previous Wi-Fi network after an import.

**Nice to have:** Quick Look preview, skip videos, a filename template, a warning when the camera resizes JPEGs.

**Out of scope:** everything in section 5.

**Order:** all Fuji Wi-Fi cameras first, then Mac polish, then Windows/Linux, then Bluetooth Fujis, then other brands.
