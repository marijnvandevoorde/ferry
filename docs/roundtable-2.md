# Round table 2: after using the app

> Simulated, like [the first round table](roundtable.md): the participants are composite personas, not real
> people. The point is to stress-test the app from different angles. Real feedback in issues and discussions wins.

Same facilitators (**Noor**, UX designer; **Sam**, product manager) and photographers (amateurs **Lea**, **Bram**,
**Jules**; pros **Femke**, **Karim**, **Anouk**). This time everyone used the app for a week: the Mac app with an
X-T20 and an X-S10, the Windows/Linux app, and `fujictl`.

## What worked

- **Lea:** It connects by itself, I press one button, the photos are in Photos. That's what I wanted.
- **Karim:** PC AutoSave is the killer feature. The camera empties itself to the laptop while I have dinner.
- **Jules:** `fujictl watch` as a systemd service, into digiKam's folder. Set it up once and forgot about it.
- **Bram:** The Pictures folder button. Windows Photos showed everything right away.

## What's missing or annoying

### During the import

**Femke:** When I import 300 photos I want to know how long it'll take. A percentage isn't enough: show the speed
and the time left.

**Karim:** And after the import, tell me *where* it went. A button to show the files in Finder or open Photos.

**Bram:** Is the disk going to be full? My laptop is always full. Warn me *before* starting, not halfway.

**Noor:** And reassure people the files are complete. Check every file's size against what the camera said and
retry if it doesn't match.

### Choosing what to import

**Femke:** On the camera I *protect* (lock) my selects during the shoot. Let me import only protected photos. That
way I cull on the camera and the app just follows.

**Anouk:** Or filter by file type. When a camera can send RAW and JPEG, I want just one of them.

**Lea:** I want to switch between newest first and oldest first. When I'm catching up on a holiday, oldest first
reads like a story.

**Jules:** Bigger thumbnails please. A size slider, like Finder.

### Organizing

**Lea:** One "Fujifilm" album gets huge. Can the album name include the date, like "Fujifilm 2026-11"?

**Karim:** Keyboard shortcuts: ⌘I to import new, ⌘⇧I to import the selection.

### Language

**Bram:** The app is in Dutch now, nice. But error messages from the camera connection are still English.

## Still out of scope

The group repeated the "no" list from round 1 (no editing, catalog, ratings, deleting from the camera).
**Femke** asked for writing copyright and author into the files; Noor and Sam decided against it, because it
changes the photographer's files, and Lightroom and Photos do it better at import time.

## Issues filed

| Request | Who | Issue |
|---------|-----|-------|
| Speed and time remaining during imports | Femke | #54 |
| Show the imported files when done | Karim | #55 |
| Check free space before importing | Bram | #56 |
| Verify file sizes, retry once | Noor | #57 |
| Import only photos protected on the camera | Femke | #58 |
| Filter by file type (JPEG, RAW, HEIF, video) | Anouk | #59 |
| Sort newest or oldest first | Lea | #60 |
| Thumbnail size slider | Jules | #61 |
| Album name with date tokens | Lea | #62 |
| Keyboard shortcuts for importing | Karim | #63 |
| Translate connection errors | Bram | #64 |
