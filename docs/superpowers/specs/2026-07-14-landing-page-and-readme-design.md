# Flint landing page + README refresh — design

## Goal

Give the Flint repo a proper GitHub Pages landing page and a more visually
inviting README before wider public sharing (Reddit, etc.). Both reuse the
app's own Carbon (Vercel/Geist-inspired) design tokens exactly — no new
palette, no invented visual identity.

## Scope

1. A standalone one-page marketing site at `ohernandezdev.github.io/flint`,
   served from a `docs/` folder on `main` (no build step, no generator).
2. A visual refresh of `README.md`: a banner/demo image near the top and a
   link to the new landing page. Existing technical content (safety model,
   architecture, build instructions) is kept as-is — it's already solid.

Out of scope: no CI/build tooling for the site (plain HTML/CSS), no custom
domain (GitHub Pages default subdomain), no additional pages beyond the one
landing page.

## Visual assets

- Screenshots are frames extracted directly from the original screen
  recording (`~/Desktop/Grabación de pantalla 2026-07-14....mov`) at full
  900x610 source resolution — not the compressed demo GIF. Six frames
  captured: ISO empty state, Windows-detected banner, choose USB drive,
  confirm-before-erasing, creating/format progress, copy progress.
- Each frame is cropped 3px from the top and left edges to remove a border
  artifact (a sliver of desktop-background color bleeding in at the rounded
  window corner).
- No emoji anywhere in the page. Feature-grid icons are small hand-authored
  inline SVGs (line style, `currentColor`, no fill) instead of emoji or an
  icon font/CDN (CSP blocks external fonts/icons in the Artifact preview;
  for the real `docs/` page, inline SVG is simplest and has zero
  dependencies either way). Comparison-table checkmarks (✓/✗) and the two
  navigational arrows (↗ ↕) are kept — they're standard monochrome
  typographic symbols, not decorative emoji.
- The GIF used in the README is a re-encoded, smaller loop (not the raw
  5.4MB capture) — optimize size/dimensions before embedding.

## Landing page sections (`docs/index.html`)

In order, top to bottom:

1. **Nav** — Flint wordmark + icon, links to How it works / Safety /
   Compare / GitHub.
2. **Hero** — eyebrow ("Open source · GPLv3"), headline, one-sentence
   lede, primary CTA ("Download for macOS" → `releases/latest`) + secondary
   CTA ("See how it works" → `#how`), a meta line (macOS 13+, universal,
   signed & notarized), and the Windows-detected screenshot as the hero
   image.
3. **How it works** (`#how`) — 4 step cards, each with a real screenshot:
   Select ISO → Choose USB → Confirm before erasing → Watch it build.
4. **Features** — 6-card grid: Windows+Linux auto-detection, USB-only
   whitelist, privileged-work isolation, optional SHA-256 verification,
   size guard for raw writes, bilingual UI + real progress. Each has a
   small line-SVG icon (no emoji).
5. **Safety model** (`#safety`) — two-column: left is the S-1..S-5
   safeguard list (tag + one-sentence explanation each, matching the
   README's existing language); right is a small architecture diagram
   (Flint.app ↔ XPC, code-signature checked ↔ FlintHelper (root)) built
   from styled `div`s, not an image.
6. **Compare** (`#compare`) — table: Flint vs. Rufus vs. Boot Camp
   Assistant vs. manual Terminal, across free/open-source, runs on macOS,
   Windows+Linux support, internal-disk protection, no-Terminal-needed.
7. **Final CTA** — requirements line + a second "Download for macOS"
   button.
8. **Footer** — icon+wordmark, links (GitHub, License, Security policy,
   Contributing), one-line closing statement.

Every color, radius, spacing, and type-weight value is pulled from
`App/DesignSystem/Carbon.swift` (see the approved preview artifact for the
exact CSS custom-property mapping). Light/dark both supported via
`prefers-color-scheme` plus `data-theme` override, matching the app's own
dynamic color approach.

## README changes

- Add a banner near the very top (below the H1, above the badges or
  integrated with them): logo + short tagline, and the optimized demo GIF
  underneath the intro paragraphs.
- Add a link to the new landing page (as a badge or a plain link near the
  top) alongside the existing release/license/platform badges.
- No other structural changes — the existing Features / Safety model /
  Requirements / Building from source / How it works / Localization /
  License / Acknowledgements sections stay as they are.

## Out of scope / explicitly deferred

- No analytics, no newsletter signup, no blog — single static page only.
- No custom domain / CNAME.
- Screenshots are not retaken from a fresh app launch; the approved set
  comes from the existing recording since it already reflects the current
  Carbon UI and Flint branding.

## Acceptance

- `docs/index.html` renders correctly opened locally as a file (no build
  step required) and once GitHub Pages is enabled for the repo.
- README renders correctly on GitHub with the new banner/GIF visible above
  the fold.
- Both light and dark GitHub/browser themes look intentional, not broken.
- No emoji in either deliverable.
