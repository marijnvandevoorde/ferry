# Round table 6: Ferry 0.2 on three systems

> Simulated, like the earlier rounds: composite personas, not real people. Real feedback in issues wins.

Ferry 0.2.0 (f88f659) is the first version on Mac, Windows and Linux. **Noor** (UX designer) and **Sam** (product
manager) sat with six people again: two from round 5 to check their fixes, four new, on all three systems. No help
unless they were stuck for over a minute. Hardware we don't have (GoPro, Ricoh, Sony) was walked through from the
code, and those parts are marked as untested.

- **Lea**: X-T20, MacBook Air. Shoots JPEG, uses Photos. Asked for the offline note and for rejoining her Wi-Fi.
- **Tom**: Canon EOS R10, Mac. Asked for the brand-neutral subtitle.
- **Dani** (new): GoPro HERO11 Black, mountain biking, mostly video, MacBook Pro.
- **Priya** (new): X-S10, Windows 11 laptop, family photos. Tried PC AutoSave.
- **Ruben** (new): Ricoh GR III, Fedora and Ubuntu, a folder synced to Immich. Reads manifests before installing.
- **Ines** (new): Sony a6000 and an iPhone. Found Ferry while browsing the Mac App Store.

## What happened

**Lea** read the offline note before joining the camera's network ("Good, that's the sentence I wanted") and
turned on **Disconnect when the import is done** straight away. Then she clicked **Import 12 New** while the card
was still being read, like she always does, and Ferry never disconnected. "I turned on the one setting I asked
for, used the one button I always use, and it didn't happen." When she waited for the whole list, it did
disconnect, and she landed on "Connect your camera" with the three setup steps. "It looks like it lost the camera,
not like it finished." She also asked which text is right: the connect screen says the Mac goes back when you turn
the camera off, the setting says once the camera closes its network.

**Tom** saw his subtitle fixed and the default album renamed. "It's not wrong any more, it's just still a Fuji app
wearing a neutral coat": both links under the steps are about Fujifilm. Then the R10 got him stuck. "Connecting…"
and a spinner for up to two minutes, no Cancel, no hint whether the camera wanted something from him. The error
told him to restart the camera's Wi-Fi; he did, same result, and auto-connect kept trying every few seconds. He
liked Connection Log ("exactly what I'd paste into an issue") but found no way from the app to send a camera
report, and the R10 isn't on the camera list.

**Dani** liked the GoPro menu path under "Where is Wi-Fi on my camera?" and the video badges. With four ride clips
of 3 to 4 GB, the bar sat at zero for minutes with no time left. "Is it frozen?" **Stop** did nothing until the
clip had finished. "I clicked Stop and it kept going. That's worse than no button." The right-click menu said
"Import 3 Photos" for three videos.

**Priya** got Windows' "Windows protected your PC" box, which nothing on the site had warned her about. She found
**Run anyway** after a minute. The **Pictures folder** preset delighted her, and PC AutoSave registered with her
X-S10. But the main window still told her to join the camera's network ("I thought the whole point was that I
*don't* do that?"), and the first AutoSave session imported about 600 photos she had already copied with her SD
slot. "Now I have every beach photo twice." On Windows there is no way to mark them as imported.

**Ruben** found the GPG signatures in the README and liked them, but not on the download page. He set Ferry to
import into his Immich-synced folder and hit the same wall as Priya: most of the card is already in Immich and
Linux has no "Mark as imported". The privacy page says the Immich key is in the system keychain; on Linux it's in
the app's local storage. "If you write that on a privacy page, it has to be true on every platform."

**Ines** stopped scrolling at the App Store name, then read "Tested on the Fujifilm X-T20" and Sony at the end of
a "maybe" list. The camera list says "Older Sony Alpha … with Wi-Fi sharing" and "media server". "Is a 2014 a6000
'older'? Just name the models, or tell me which menu item to look for." On first launch at home the subtitle said
"Looking for the camera on your Wi-Fi network…" while step 2 said to join the camera's network. "Which one is it?"

## What they asked for

| # | Feedback | Who | Seen |
|---|----------|-----|------|
| 1 | Mark photos as already imported on Windows and Linux too, before AutoSave takes the whole card | Priya, Ruben | 2 of 6, round 5's blocker again for every non-Mac user |
| 2 | Tell me whether my camera is meant: R10 missing, "older Sony" unclear | Tom, Ines, Priya | 3 of 6 |
| 3 | "Disconnect when the import is done" should actually happen, and finish on a clear done screen | Lea | 1 of 6, the setting she asked for failed |
| 4 | While connecting: say it's waiting on the camera, offer Cancel, stop retrying a camera that refuses | Tom | 1 of 6, stuck for two minutes |
| 5 | Fewer Fujifilm links on the first screen, and a subtitle that matches the steps | Tom, Ines | 2 of 6 |
| 6 | Warn about Windows' "protected your PC" box; put the Linux signatures on the download page | Priya, Ruben | 2 of 6 |
| 7 | Privacy page must be true on every platform (Immich key) | Ruben | 1 of 6, every Windows and Linux Immich user |
| 8 | PC AutoSave on Windows: say so on the main screen, start at login, don't fail silently without a folder | Priya | 1 of 6 |
| 9 | Progress and a working Stop for big video files | Dani | 1 of 6, "Is it frozen?" |
| 10 | Send a camera report from the app | Tom | 1 of 6 |
| 11 | Low-battery warning on Fujifilm, and during the import | Lea | 1 of 6 |
| 12 | Say "items" when it isn't only photos; no empty "Only Protected Photos" on cameras without it | Dani, Ines | 2 of 6, small |
| 13 | RPM package, Flatpak built from source | Ruben | 1 of 6 |

## Product decisions

**Sam:** Number 1 is round 5's blocker coming back on two new systems, and AutoSave makes it worse because it
doesn't ask first. Port it before anything else. Number 3 is a plain bug in the one setting Lea asked for.

**Noor:** And number 4 is the worst screen we have: a spinner with no exit. Tom and Ines both say the first screen
is still Fuji's. Grouping the two links fixes that without hiding Bluetooth from X-T5 owners. The rest is mostly
words on the site.

Decided, in this round:

1. **Mark as imported on Windows and Linux.** `ferryctl serve` gets a `mark` command (ids, imported or not) on top
   of ImportHistory's insert and remove. The desktop app gets the right-click menu (Import, Mark as Imported / Not
   Imported) and the first-connection notice, with the Mac's wording. An AutoSave session never auto-imports on a
   camera that has 30 or more photos and no Ferry history: it shows the notice instead.
   *Sources/ferryctl/Serve.swift, apps/desktop/src/main.ts, apps/desktop/index.html.*
2. **Disconnect when the import is done, for real.** When Import New finds nothing left after the listing, run
   the disconnect check too. Afterwards auto-connect stays paused until the user presses Connect or the camera's
   address stops answering (a plain TCP check, no handshake), instead of 60 seconds. The connect screen then shows
   a done state: the summary with Open Photos / Show in Finder, "You can turn the camera off now.", steps
   collapsed. Until it is checked on an X-T20, both texts say the same honest thing: "Ferry lets go of the camera
   after the import. Turn the camera off and this Mac goes back to your usual Wi-Fi."
   *App/CameraModel.swift, App/ConnectView.swift, App/SettingsView.swift, apps/desktop/index.html.*
3. **A way out while connecting.** A Cancel button while connecting or waiting (back to searching, auto-connect
   paused until Connect). PTP/IP reports that it is waiting once the init request is sent, so the screen says
   "Check the camera. It may be asking whether to allow this Mac." After a failure that isn't "camera not found",
   auto-connect pauses until Connect instead of retrying every 3 seconds. A PTP/IP rejection gets its own text:
   "The camera refused the connection. It may need pairing that Ferry doesn't support yet." Camera error codes go
   to the log; the screen says "The camera refused a request. Details are in Connection Log." Below any connection
   error: a **Send a camera report…** link to the report form.
   *Sources/FerryKit/PTPIPCamera.swift, Sources/FerryKit/PTP.swift, App/CameraModel.swift, App/ConnectView.swift.*
4. **First screen for every brand.** The two Fujifilm links become one line: "Fujifilm: Stay online with PC
   AutoSave · Pair over Bluetooth (X-T5 and newer)". With auto-connect on, the subtitle reads "Join the camera's
   Wi-Fi network and Ferry connects by itself." on Mac and desktop.
   *App/ConnectView.swift, apps/desktop/index.html.*
5. **Camera list says who is meant.** Canon gets a row "Other EOS models with Wi-Fi": experimental, with the note
   that models asking for Camera Connect pairing may not work yet (#52). The Sony row names the test Ines asked
   for: "Sony Alpha with Send to Smartphone in the playback menu". The FAQ stops saying Bluetooth pairing isn't
   supported: it's in the Mac app, not yet tested on a real camera (#46).
   *site/cameras.json, site/i18n/en.json.*
6. **Download block and privacy page.** Under the Windows button: "Windows may say it protected your PC: choose
   More info, then Run anyway. A signed installer is coming (#42)." Next to the Linux buttons: a Signature link
   per file and the key fingerprint. The privacy page says where the Immich key is per system: the keychain on a
   Mac, the app's settings on this computer on Windows and Linux.
   *site/i18n/en.json, site/templates/home.html.*
7. **PC AutoSave on Windows and Linux.** When AutoSave is on, the connect screen says "Waiting for your camera to
   send photos (PC AutoSave)" above the steps. An AutoSave session without a folder shows "Choose a folder to
   import into first." and a notification instead of disconnecting silently. Turning AutoSave on also ticks Start
   at login, and the text says Ferry keeps running in the tray.
   *apps/desktop/src/main.ts, apps/desktop/index.html.*
8. **Big files over HTTP.** HTTP downloads report bytes as they arrive (a download delegate), so the bar and time
   left move during a GoPro clip, and Stop cancels the running download instead of waiting for it.
   *Sources/FerryKit/HTTPCameras.swift, App/CameraModel.swift.*
9. **Words that fit every camera.** The right-click menu says "Import 3 Items". "Only Protected Photos" only shows
   for cameras that report protection (PTP).
   *App/GalleryView.swift, App/CameraModel.swift.*

Not now:

- **Fujifilm battery (11).** The X-T20 doesn't report the standard battery property (0x5001) in the transfer mode
  Ferry uses. Fujifilm's own property (0xD242) only shows up in remote shooting mode, going by vcam's traces, and
  its scale is unknown. The warning works for GoPro and Ricoh; Fujifilm needs a real camera that reports it.
- **Immich key in the system keyring (7).** Decision 6 makes the page true today. A keyring on Windows and Linux
  (and through the Flatpak portal) is worth its own issue.
- **RPM and Flatpak from source (13)** stay with #43.
- **GoPro keep-alive during an import, resuming a cut-off clip, GPR as RAW:** none of it is tested on a real
  GoPro. Wait for the first GoPro camera report.
- **Ricoh card listing** (one request per file, the full list again on every keep-alive): mock API only. Ruben
  offered a GR III report; fix it against a real response.
- **AutoSave mark per model** on the camera list: no model has been tried with AutoSave on a real camera yet.
- **App Store name** (Ines liked "Ferry: Camera Photo Import") is settled with the submission (#23). Her reaction
  counts for the descriptive name.
- **"Full-size originals, not phone copies"** in the listing: only once a real Sony shows what DLNA delivers.
