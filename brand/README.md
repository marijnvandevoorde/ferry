# Ferry — Brand package

Version 1.0 · 3 November 2026

This package is the handoff reference for the Ferry website and desktop-app implementation.
It contains editable SVG source assets, colour tokens, usage guidance and implementation notes.

## Brand idea

**Your photos, carried safely home.**

Ferry is a calm, crafted desktop utility that brings photographs from a camera to a computer over Wi-Fi.
The identity should communicate care, continuity and safe arrival — not speed, cloud storage or gadgetry.

## Identity direction

- A modest passenger-ferry silhouette, not a yacht or cruise ship.
- A restrained serif wordmark paired with a simple geometric vessel mark.
- Night blue and warm paper are the principal surfaces.
- The orange hull is the distinctive identifying detail.
- Water lines are secondary and should disappear in the smallest-size glyphs.
- Tone: calm, warm, quietly confident, independent and carefully made.

## Package contents

### `logos/`
- `ferry-wordmark-light.svg` — dark ink mark and wordmark on warm-paper background.
- `ferry-wordmark-dark.svg` — warm-paper wordmark and orange hull on night-blue background.
- `ferry-mark-color.svg` — standalone full-colour transparent symbol.
- `ferry-mark-mono-dark.svg` — one-colour dark symbol.
- `ferry-mark-mono-light.svg` — one-colour light symbol.

### `icons/`
- `ferry-app-icon-dark.svg` — dark macOS-style rounded-square icon.
- `ferry-app-icon-light.svg` — light alternative.
- `favicon.svg` — compact, simplified browser icon.
- `ferry-menubar-template.svg` — monochrome template glyph source.

### `web/`
- `ferry-tokens.css` — CSS custom properties for the brand palette and typography.

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
