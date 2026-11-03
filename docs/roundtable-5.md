# Round table 5: showing Ferry to the people it's for

> Simulated, like the earlier rounds: composite personas, not real people. Real feedback in issues wins.

Round 4 decided the audience: enthusiasts and families without a card reader at hand. So this time **Noor** (UX
designer) and **Sam** (product manager) sat next to five of them while they used the Mac app (Ferry 811ebf1) for
the first time, with their own camera and their own Mac. No help unless they were stuck for over a minute.

- **Lea**: X-T20, MacBook Air with only USB-C. Shoots JPEG, uses Photos.
- **Bram**: X-S10, family photos and holidays. Card has two years of photos on it; copied most of them with a
  borrowed reader last spring.
- **Jules**: X-E4, likes keyboard shortcuts, imports to a folder.
- **Mira** (new): X-A5, her first camera, got it as a gift. Never changed a camera setting.
- **Tom** (new): Canon EOS R10, came from the brand-neutral site. Knows Macs well.

## What happened

**Lea** had photos in Photos in under two minutes. She stopped once: after joining the camera's network, Mail
said she was offline. "Did I break my Wi-Fi?" When she turned the camera off, the Mac went back to her home
network by itself. "Nobody told me that would happen. I'd have panicked if I was in the middle of a video call."

**Bram** connected fine and then saw **Import 1,412 New**. "No. Most of those are already on my Mac." He didn't
want to click it, and there was no way to tell Ferry which ones he already had. He selected the last three
days by hand (section header **Select**, three times) and imported those. The next time he connects, Ferry will
offer the old 1,400 again. "So every time I'll have to do this? Then I'll just stop using it."

**Jules** right-clicked a photo out of habit. Nothing happened. He found everything in the toolbar menus, but
"on a Mac, right-click is where I look first." He also wanted to undo an import by mistake into the wrong album:
mark it as not imported so it shows up as new again, without forgetting the whole history.

**Mira** followed the three steps on the connect screen literally and it worked. Her only question was the
album: "Why is my album called Fujifilm? I'd look for it under the date." She left it.

**Tom** (Canon) got stuck at the subtitle: *Import photos from your Fujifilm camera over Wi-Fi.* "The site said
any camera. Is this the wrong app?" He went on anyway; the Canon connection is experimental and failed on his
R10, which he expected from the cameras page.

## What they asked for

| # | Feedback | Who | Seen |
|---|----------|-----|------|
| 1 | Tell Ferry "I already have these" so Import New stops offering them | Bram, Jules | 2 of 5, blocks Bram completely |
| 2 | Right-click a photo: import, preview, mark as (not) imported | Jules, Tom | 2 of 5 |
| 3 | Warn that the Mac is offline while on the camera's network | Lea, Mira | 2 of 5 |
| 4 | Don't say Fujifilm where it isn't needed | Tom | 1 of 5, but every non-Fuji user |
| 5 | Album named by date or camera instead of "Fujifilm" | Mira | 1 of 5 |
| 6 | Rejoin home Wi-Fi automatically after the import (#21) | Lea | 1 of 5 |
| 7 | Delete photos from the camera after importing | Bram | 1 of 5 |

## Product decisions

**Sam:** Number 1 is the only thing that made someone say they'd stop. It hits exactly our audience: people
who used to copy photos some other way and now switch. Fix it two ways: a one-time notice when a camera has a
lot of photos and none of them came through Ferry yet, and a permanent way to mark any photo as imported or not.

**Noor:** And put that in a right-click menu, so number 2 comes with it. Same actions as the toolbar, nothing new
to learn.

Decided, in this round:

1. **Mark as imported / not imported.** In the Select menu (for the selection) and on right-click (for the
   clicked photo, or the whole selection if the photo is part of it). Only changes Ferry's history; nothing
   is copied or deleted.
2. **First-connection notice.** When a camera shows 30 or more photos and none were imported by Ferry: "Already
   copied these some other way? Mark them as imported, and Import New will only pick up photos you take from
   now on." Buttons: **Mark All as Imported**, and close. Shown once per camera.
3. **Right-click menu on photos:** Import, Quick Look, Mark as Imported / Not Imported.
4. **Offline note** on the connect screen: while the Mac is on the camera's network it has no internet, and it
   goes back to the usual network when the camera's Wi-Fi turns off.
5. **Brand-neutral subtitle:** "Import photos from your camera over Wi-Fi."

Not now:

- **Album name (5).** Changing the default would move existing users' new photos into a different album
  without asking. Tokens already work (`{yyyy}-{MM}`); revisit with a first-run destination choice.
- **Rejoin Wi-Fi (6)** stays issue #21: it needs a real camera to test, and the note in decision 4 covers the
  surprise for now.
- **Delete from camera (7):** as far as we know, Fujifilm's Wi-Fi modes don't offer deleting. Check on a real
  camera before promising or ruling it out.
