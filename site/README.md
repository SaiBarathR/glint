# Glint website

The site at https://saibarathr.github.io/glint/, built with [Astro](https://astro.build) into plain static files.
The only JavaScript on the pages is a few small scripts (theme, copy buttons, download links, gallery filter).

```sh
cd site
npm ci
npm run dev       # http://localhost:4321/glint/
npm run build     # static site in site/dist
npm run preview   # serve site/dist
```

`.github/workflows/pages.yml` builds and deploys it on every push to `main` that touches `site/`, `gallery/`,
`docs/` or `App/Resources/Extensions/`.

## Where the content comes from

| Page | Source |
| --- | --- |
| Extension reference (`/docs/reference/`) | `docs/EXTENSIONS.md`, rendered as is (the single source of truth) |
| Getting started, Writing extensions, Safety and limits | `site/src/guides/*.md` |
| Changelog | `docs/releases/*.md`, newest version first |
| Extensions: included | `App/Resources/Extensions`, read at build time |
| Extensions: gallery | `gallery/` plus `gallery/catalog.json` (categories and examples); each item's `.glintextz` is zipped at build time |

Screenshots in `public/images` were rendered with `Glint --render-bar` / `--render-settings`.

## Design

Neutral stone greys, charcoal and one solid amber accent (`#ffbe36`, from the icon's highlighted line). No purple and
no gradients anywhere, including images and code highlighting (`src/lib/code-themes.mjs` recolours GitHub's themes).
The site uses its own neutral mark (`src/assets/glint-mark.svg`, `public/favicon.*`) rather than the purple app icon.

## Videos

Drop `public/media/demo.mp4` and `public/media/promo.mp4` in and rebuild. Until a file exists, its slot shows the
poster (`demo-poster.webp` / `promo-poster.webp`, 1280×720) with a "Video coming soon" label instead of a player.

Icons are from [Lucide](https://lucide.dev) (ISC license), drawn inline at build time; SF Symbol names in extension
configs are mapped to them in `src/lib/icons.ts`.
