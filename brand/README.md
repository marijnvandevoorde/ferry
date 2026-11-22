# Ferry — Brand package

Version 2 · 22 November 2026 (v1: 3 November 2026)

This package is the handoff reference for the Ferry website and desktop-app implementation.
It contains editable SVG source assets, colour tokens, usage guidance and implementation notes.
The designer's guide is `guides/Ferry-Brand-Guidelines-v2.pdf`.

## Identity direction

- A side-on passenger ferry: navy superstructure, warm orange hull stripe, understated wake.
- The scenic app icon (ship on layered water) is the expressive application mark; the flat ship is for small
  and one-colour uses.
- A restrained serif wordmark (Newsreader) next to the ship.
- Night blue and warm paper are the principal surfaces. The orange hull is the distinctive detail.
- Tone: calm, warm, quietly confident, independent and carefully made.

## Package contents

### `logos/`
- `ferry-mark-color.svg` — full-colour ship for light surfaces (its paper decks blend into the paper).
- `ferry-mark-mono-navy.svg`, `ferry-mark-mono-light.svg` — one-colour ship.
- `ferry-lockup-light.svg`, `ferry-lockup-dark.svg` — ship, wordmark and tagline (Georgia fallback text).

### `icons/`
- `ferry-app-icon-scenic.svg` — the app icon. The package's version let the water run past the rounded
  corners; this copy clips it to the rounded square.
- `ferry-app-icon-dark.svg`, `-light.svg`, `-mono.svg` — alternative icons with a small ship; not used.

### `illustrations/`
- `ferry-social-preview.svg` — the social card. `site/tools/mockups/og.html` renders it with Newsreader and Inter.

### `derived/` (made here from the ship, not part of the designer's package)
- `mark-color-dark.svg` — the ship for dark surfaces: paper decks and mast, as in the dark lockup.
- `favicon.svg`, `app-icon-small.svg`, `menubar.svg` — the ship simplified for 16–32 px: decks with the window
  row cut out, a gap, then the hull. No mast or wake.

### `web/`
- `ferry-tokens.css` — CSS custom properties for the brand palette and typography (unchanged in v2).

`export.sh` renders all of this into the Mac app, the Windows/Linux app and the site icons.

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
- At 16 px, use the simplified favicon; do not scale down the full ship illustration.
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

1. Treat the SVGs as editable starting assets, not raster exports.
2. Preserve the mark's proportions; never stretch it.
3. Keep the orange hull as the principal accent in full-colour uses.
4. Use mono assets for one-colour contexts; do not simulate monochrome with opacity.
5. Do not add gradients, shadows, glow, outlines or 3D effects to the logo.
6. The wordmark artwork uses a Georgia/Times fallback. For production, render the wordmark using the approved Newsreader font or convert final lettering to outlines after approval.
7. The SVG app icons are scalable previews/source. Export platform-specific PNG/ICNS/ICO assets as required by the build pipeline.
8. Before release, validate the favicon and menu glyph at native sizes on real browsers and macOS menu bars.

## File naming
Use lowercase kebab-case. Keep source SVGs in version control. Export platform binaries into the app's existing asset pipeline rather than committing generated build artifacts here.
