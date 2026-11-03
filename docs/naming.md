# Round table 3: a name

> Simulated, like [round 1](roundtable.md) and [round 2](roundtable-2.md): composite personas, not real people.

Same panel: **Noor** (UX designer), **Sam** (product manager), amateurs **Lea**, **Bram** and **Jules**, pros
**Femke**, **Karim** and **Anouk**.

## Why rename

**Sam:** "Fuji Import" describes v0.1. The app now also talks to Canon, Olympus, Ricoh, Sony and Panasonic
cameras, runs on Windows and Linux, and "Fuji" is Fujifilm's trademark. The App Store and the Microsoft Store
don't like a third-party app named after a camera brand either.

**Noor:** The name should say *your photos come to you*, be easy to say in Dutch, French, German, Spanish and
Italian, and work as a small word next to an icon.

## What we want

- Short: one word, two syllables at most.
- Not a brand name, not "Fuji", not "Cam…" or "…Sync" (there are hundreds).
- A verb or a picture of moving something from A to B, because that is all the app does.
- Searchable when combined with "camera" or "photo import".

## Shortlist

| Name | Idea | For | Against |
|------|------|-----|---------|
| **Ferry** | Carries your photos across, back and forth, on a schedule | Calm, friendly, works in every language, nice icon (a little boat with a photo) | Common word, so SEO needs "Ferry photo import" |
| Pigeon | A homing pigeon: photos fly home by themselves (PC AutoSave) | Memorable, fun | Pros: "too cute for a work tool"; existing brands |
| Offload | What pros call copying cards | Exactly right for pros | Means nothing to amateurs; used by Hedge and others |
| Homing | Photos find their way home | Matches PC AutoSave | Hard to say in French and Spanish |
| Shoebox | Where prints used to go | Warm | Sounds like storage, and we're not a catalog |
| Unspool | Film metaphor | Fuji film simulation fans would like it | Hard to spell, slightly negative |
| Courier | Delivers your photos | Clear | Feels like a shipping company |
| Airlift | Photos over the air | Clear | Military, and close to AirDrop |

## Discussion

**Lea:** I'd tell a friend "use Ferry". I wouldn't say "use Offload".

**Karim:** Offload is the word I use, but Ferry doesn't bother me, and it's not an existing pro tool.

**Femke:** Pigeon made me smile, but I don't want a pigeon on my invoices.

**Jules:** Ferry is also nice for the Linux CLI: `ferry watch ~/Pictures`.

**Anouk:** In Dutch, "veer" or "pont", but nobody minds the English word. Same in German, French and Italian.

**Noor:** Ferry gives us a calm visual language: water, horizon, crossing. The icon can stay the lens with the
arrow for now.

**Sam:** Ferry it is, as a working name. Before launch: check trademarks in the EU and US, the App Store,
the Microsoft Store and a domain. The website reads the name from one setting (`site/site.json`), so changing
it later is a one-line change. Renaming the apps themselves is a separate step.

## Decision

Working name: **Ferry**. Runner-up: **Offload**, then **Pigeon**.

**Update:** [round 4](roundtable-4.md) replaced Ferry with **Haven**.

**Update 2:** after round 4 the owner chose to keep **Ferry**. The tagline from that round stays in spirit:
"Your photos, carried safely home".
