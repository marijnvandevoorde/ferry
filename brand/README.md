# Ferry — Brand package

Version 3 · 22 November 2026 (restored scenic direction; supersedes v2 of the same day and v1 of 3 November)

This folder is the handoff reference for the Ferry website and apps. The designer's guide is
`guides/Ferry-Brand-Guidelines-v3.pdf`.

## Identity direction

- The hero is the scenic app icon: a front-side three-quarter passenger ferry with layered decks, a warm orange
  hull, dusk sky, deep-blue sea and reflected sunset light. Use it for the app icons and larger brand moments.
- Secondary: the wordmark and tagline. Small sizes: the compact one-colour ferry glyph, only where space or
  platform conventions demand it (menu bar, site and app headers).
- Do not replace the hero with a generic side-on pictogram (v2's direction, dropped).

## Contents

### `reference/` (as delivered, raster)
- `ferry-app-icon-master-1024.png` — the scenic icon. A crop from the reference board, upscaled from about
  135 px, so it is soft above 256 px. Replace it with the original full-resolution artwork when there is one.
- `ferry-lockup.png`, `ferry-menu-glyph.png`, `reference-board.png` — crops and the board they come from.

### `icons/`
- `ferry-app-icon.png` — made by `export.sh` from the master: the board's off-white trimmed off the corners
  and edges, cut to a clean rounded square on transparency. Everything else is rendered from this file.

### `derived/`
- `glyph.svg` — the compact glyph (the 24 px one in `reference/ferry-menu-glyph.png`), traced to a vector with
  potrace. One colour; the menu bar template and the inline header marks use it.

### `web/`
- `ferry-tokens.css` — CSS custom properties for the palette and typography (unchanged in v3).

`export.sh` renders the Mac, Windows/Linux and site icons. The social card is
`site/tools/mockups/og.html`.

## Colour tokens

| Name | Hex | Intended use |
|---|---|---|
| Night Blue | `#1B2440` | Primary dark surface, hero, dark app chrome |
| Dusk Violet | `#3B3A6B` | Secondary dark surface, subtle depth |
| Horizon Glow | `#F4A26B` | Warm highlight, arrival moments |
| Signal Vermilion | `#C9472B` | Primary actions, hull accent |
| Warm Paper | `#FBFAF7` | Primary light surface |
| Ink | `#1C2233` | Primary text and light-mode icon detail |

Do not use orange as body text on paper; reserve it for large accents and solid controls.
Check text contrast independently for every UI pairing.

## Typography

Preferred pairing:
- Editorial / brand display: **Newsreader** (serif).
- UI / product interface: **Inter** (sans-serif).

If these fonts are unavailable, use a high-quality system serif for display and the native system UI font for controls.
Do not force the editorial serif into dense interface text.

## Usage rules

### Website
- Light sections use Warm Paper and Ink.
- Dark hero sections use Night Blue, optionally transitioning visually into Dusk Violet.
- Use Horizon Glow as a small point of warmth, not a general highlight colour.
- Use Signal Vermilion for the main download action and occasional important emphasis.
- Keep layouts spacious, editorial and image-led. Prefer real photography over generic tech illustrations.

### Desktop application
- Prioritise native platform conventions and legibility over brand decoration.
- Use the ship mark as a restrained identity cue; do not place a large decorative logo in every view.
- Use clear status language: “Ready to import”, “Importing”, “Safely home”.
- The product is local-first. Avoid cloud metaphors and cloud-service visual language.

### Small sizes
- Keep the scenic icon at 16–64 px (favicons, small app icons); use the glyph only where a one-colour mark is needed.
- Menu bar artwork must be a single-colour template image with transparency. The SVG is a source reference; export to the platform's required template format and verify against both light and dark menu bars.
- App icon: keep the rounded-square silhouette and strong ship/hull contrast. Test at 16, 32, 64, 128, 256 and 512 px.

## Voice

Prefer:
- “Bring your photos home.”
- “Ferry remembers what you’ve imported.”
- “Your new photos have arrived.”
- “Nothing new to bring across.”

Avoid:
- “Lightning-fast sync”
- “Cloud photo management”
- “Revolutionary transfer technology”
- Cute nautical puns or overly playful status messages.

## Implementation notes for agents

1. The scenic icon is raster artwork; the glyph is the only vector. Don't redraw the scenic icon in another style.
2. Preserve the mark's proportions; never stretch it.
3. Keep the orange hull as the principal accent in full-colour uses.
4. Use mono assets for one-colour contexts; do not simulate monochrome with opacity.
5. Do not add shadows, glow, outlines or 3D effects to the glyph.
6. The lockup in `reference/` is a raster crop. Set the wordmark in Newsreader rather than reusing the crop.
7. Platform icon sets come from `export.sh`; don't use the package's pre-made exports (they keep the board's off-white corners).
8. Before release, validate the favicon and menu glyph at native sizes on real browsers and macOS menu bars.

## File naming
Use lowercase kebab-case. Keep source SVGs in version control. Export platform binaries into the app's existing asset pipeline rather than committing generated build artifacts here.
