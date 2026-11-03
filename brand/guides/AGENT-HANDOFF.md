# Agent handoff — Ferry brand implementation

Use this brief alongside `README.md`.

## Objective
Implement the Ferry identity consistently across the marketing website and desktop app (macOS, Windows, Linux).

## Required assets
- Website header: use `logos/ferry-wordmark-light.svg` on light surfaces and `logos/ferry-wordmark-dark.svg` on dark surfaces.
- Website favicon: `icons/favicon.svg`.
- App icon: start from `icons/ferry-app-icon-dark.svg`; generate the required native platform formats and validate at small sizes.
- macOS menu bar: use `icons/ferry-menubar-template.svg` as the monochrome source; export as a template image with transparency.

## Theme behaviour
- Light: Warm Paper background, Ink text, Signal Vermilion primary action.
- Dark: Night Blue background, Warm Paper text, Dusk Violet for secondary depth.
- Horizon Glow is a restrained highlight, not a general-purpose text colour.
- Preserve semantic contrast; do not assume palette pairs automatically meet accessibility requirements.

## Brand behaviour
- Keep the ship small and confident.
- Do not introduce camera, shutter, Wi-Fi, cloud, lightning or circuit motifs.
- Do not add gradients or effects to the core logo.
- Keep product copy local-first and reassuring. Ferry imports to Apple Photos, a folder or Lightroom; it is not a cloud service.
- Describe the import memory plainly: Ferry remembers previously imported photos and brings across new ones.

## Before shipping
- Check logo lockups at actual header sizes.
- Check favicon at 16×16 and 32×32.
- Check menu glyph in both light and dark menu bars.
- Check app icon at 16, 32, 64, 128, 256 and 512 px.
- Verify SVG rendering and font fallback on macOS, Windows and Linux.
- Keep source SVGs in version control and document generated platform exports.
