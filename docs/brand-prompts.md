# Prompts for the logo and website art

Prompts to paste into ChatGPT (with image generation), in order. Do step 1 first. Pick a direction before
generating anything, then reuse the chosen direction in every later prompt so the assets match.

Every prompt starts with the **brief** below. Paste it once at the start of the conversation; later prompts
assume ChatGPT still has it.

## The brief (paste first)

```
I'm designing the brand for Ferry, a free, open-source desktop app (Mac, Windows, Linux). It copies photos from a
camera to your computer over Wi-Fi, no cable or card reader: into Apple Photos, a folder or Lightroom. It
remembers what it already imported, so next time you only get the new photos.

Tagline: "Your photos, carried safely home."

Who it's for: enthusiast photographers and families, roughly 30 to 65. People who own a proper camera (often a
Fujifilm, sometimes Canon or others), take it on walks, holidays and family days, and shoot JPEG. They have a
modern laptop without a card slot and no card reader at hand. They care about photography as a craft but they
are not professionals; pros have card readers and are not the audience. They value things that are calm,
well made and trustworthy, the way a good camera strap or a Leica-era manual feels. They distrust anything
that looks like a cloud service, a subscription or a gadget toy.

The name: a ferry carries things across water and brings them safely to the other shore. The photos make a
short, quiet crossing from the camera to the computer. "Home" and "safe arrival" matter more than speed.

Tone: calm, crafted, quietly confident. Warm, not cute. Grown-up, not corporate. Think independent Mac app,
good editorial design, a small ferry crossing at dusk. NOT childish, cartoonish, mascot-like, bubbly or
"techy" (no circuit lines, no glowing wifi waves, no clouds, no lightning bolts, no camera-shutter clichés,
no 3D gloss).

Existing colours on the website (keep or refine):
- Night blue #1b2440 and dusk violet #3b3a6b (hero background, a dusk over the water)
- Warm glow #f4a26b (the last light on the horizon)
- Accent red-orange #c9472b (buttons, like a ferry's hull or a lifebuoy)
- Paper #fbfaf7, ink #1c2233

It must work as a macOS app icon (rounded square), a 16 px favicon, in a menu bar as a one-colour template
glyph, and next to the word "Ferry" in the site header.
```

## 1. Brainstorm (words only, no images yet)

```
Before drawing anything, brainstorm. Give me 10 distinct logo concepts for Ferry. For each one:
- a name for the concept and a one-sentence idea,
- the shapes involved, described concretely (what you would actually draw),
- why it fits the audience in the brief, and the risk (cliché, too literal, illegible at 16 px, too close to
  a known brand),
- how it reduces to a single-colour menu bar glyph.

Spread the concepts across different territories: literal (a boat, a crossing), abstract (a line meeting a
shore, two banks), typographic (a wordmark or monogram F), photographic (a frame, a print, a horizon), and at
least one unexpected idea. No mascots and nothing cute.

Then rank your top 3 for this audience and say why. Don't generate images yet.
```

Follow-ups worth asking:

```
Which of these would still be recognisable as a 16 px favicon and as a one-colour menu bar icon? Be strict.
```

```
Which concepts look too much like an existing logo (ferry companies, Photos, Lightroom, Dropbox, WeTransfer,
camera brands)? Drop or change those.
```

## 2. Sketch the top directions

```
Generate one image per concept for your top 3 concepts (and concept number __ from the list). Show each as a
flat vector logo mark on a plain off-white background (#fbfaf7), centred, lots of space around it, no text,
no mockups, no shadows or gradients. Same line weight style across all of them so I can compare the ideas,
not the rendering.
```

```
For the concept I like, show 4 variations: more geometric, more hand-drawn/editorial, bolder for small sizes,
and a version that uses negative space.
```

## 3. Refine the chosen mark

Replace `[CONCEPT]` with a short description of the chosen direction.

```
We're going with [CONCEPT]. Refine it into a final logo mark:
- flat vector style, built on simple geometry, even stroke or solid shapes
- two colours at most from the palette in the brief; also show a one-colour version in ink #1c2233 and a
  reversed version in paper #fbfaf7 on night blue #1b2440
- must stay readable at 16 px: show it at 512, 64, 32 and 16 px side by side on one sheet
- no text in the mark
```

```
Now pair the mark with the wordmark "Ferry". Show three typographic treatments: a humanist sans (like
Söhne/Inter), a warm serif (like Tiempos/Source Serif), and a rounded geometric sans. Mark to the left of the
word, horizontally aligned. Plain background, no mockup. Recommend one for this audience.
```

## 4. App icon

```
Turn the final mark into a macOS app icon, 1024 × 1024, following the current macOS icon style: a rounded
square (squircle) filling the canvas with the standard macOS margin, a subtle depth that isn't glossy, the
mark centred. Background: a dusk gradient from night blue #1b2440 to dusk violet #3b3a6b with a thin warm
horizon of #f4a26b. The mark in paper #fbfaf7 or the accent #c9472b. No text. Calm, premium, not toy-like.
```

```
Make a dark-mode and a "tinted" (single colour, greyscale) version of the same icon, as macOS now offers.
```

```
Make the menu bar version: the mark as a solid black glyph on transparent background, 44 × 44 px with about
4 px padding, no thin details that disappear at 22 pt.
```

## 5. Website art

These replace or join the existing site images (`site/img/`). Keep the chosen mark and palette in every prompt.

### Hero illustration

The hero is a dusk over the water (night blue to violet with a warm glow). This illustration sits beside the
headline "Get the photos off your camera. No cable."

```
Create a wide illustration, 1600 × 1100, for the website hero. Scene: a calm stretch of water at dusk, in
the palette from the brief. A small, simple ferry crosses from a near shore to a far shore where a warm
lit house window glows. On the ferry's deck: a small stack of photo prints. Flat, editorial illustration
style with soft grain, generous negative space on the left for the headline, no people's faces, no text, no
devices. Quiet and warm, like a book cover, not a cartoon.
```

Alternative if the illustration feels too literal:

```
Same scene, but more abstract: only the horizon line, the water as a few horizontal bands, a single small
geometric shape crossing, and a warm point of light on the far side. Minimal, like a Swiss travel poster.
```

### Social preview card (og-card.png)

```
Create a 1200 × 630 social sharing card. Left half: the logo mark and the wordmark "Ferry" in paper #fbfaf7,
with the tagline "Your photos, carried safely home." underneath in a smaller size. Right half: a cropped part
of the hero scene. Background night blue #1b2440. Keep all text at least 60 px from the edges. Spell the text
exactly as given.
```

### How it works (3 spot illustrations)

The page explains three steps. Make them a set: same size, same style, same line weight.

```
Create three small square spot illustrations, 600 × 600 each, as a matching set in the same flat editorial
style and palette as the hero, on a transparent or paper #fbfaf7 background, no text:
1. A camera with its Wi-Fi switched on: a simple mirrorless camera seen from the back, a small warm light on
   its screen. No wifi-wave clichés; show "ready to send" with light instead.
2. A laptop on a table with a small ferry shape arriving at its screen edge, as if docking.
3. A tidy grid of photo prints arriving in an album, one of them still sliding into place.
```

### Feature icons

```
Create a set of 6 line icons, matching the logo's stroke weight, 48 × 48, ink #1c2233 on transparent, for:
only new photos, Apple Photos or a folder, works over home Wi-Fi, free and open source, no account or cloud,
resumes after a dropped connection. Simple, consistent corner radius, no fills except one small accent
#c9472b detail per icon at most.
```

### Empty and error states in the app (optional)

```
Create two small illustrations, 400 × 300, same style as the spot illustrations, for the app:
1. "Looking for your camera": the ferry waiting at an empty dock at dusk.
2. "Everything is imported": the ferry moored, the far house window lit, calm water.
No text.
```

## After generating

- Ask for the final mark and icons as **SVG** where ChatGPT can, or redraw the chosen mark as an SVG by hand:
  generated PNGs aren't clean enough for a 16 px favicon or a menu bar template.
- Sizes the site uses today: `icon-32.png`, `icon-64.png`, `icon-180.png`, `icon-192.png`, `icon-512.png`,
  `og-card.png` (1200 × 630). The Mac app icon goes in `App/Assets.xcassets/AppIcon.appiconset`.
- Check the result against the brief with a fresh prompt: "Here is the logo. For the audience in the brief,
  what feels childish, generic or off? Be blunt."
- Run a trademark search on the final mark before using it.
