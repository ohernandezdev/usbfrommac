# Flint Landing Page + README Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a static GitHub Pages landing page for Flint and refresh the README with a banner/demo GIF and an origin-story section, all reusing the app's own Carbon design tokens, before wider public sharing.

**Architecture:** A single self-contained `docs/index.html` (inline CSS, inline SVG icons, embedded screenshots as file references under `docs/assets/`) served by GitHub Pages from `main` / `docs/`. No build step, no JS framework, no external font/icon dependencies. README changes are additive (new sections + images), no restructuring of existing content.

**Tech Stack:** Plain HTML5 + CSS custom properties (no framework), ffmpeg/PIL for image prep (already done this session), GitHub Pages (Settings → Pages → Deploy from branch → `main` / `docs`).

## Global Constraints

- No emoji anywhere in either deliverable (comparison-table ✓/✗ and directional arrows ↗/↕ are standard typographic symbols, not emoji, and are fine).
- Every color/radius/spacing/type value must match `App/DesignSystem/Carbon.swift` exactly (see values inlined in Task 2).
- Light and dark mode both supported via `prefers-color-scheme` + `data-theme` attribute override.
- Screenshots come from the already-extracted, already-cropped frames in this session's scratchpad (900x610 source, cropped 3px top/left to remove a border artifact) — not the compressed demo GIF, not new screenshots.
- Landing page repo: `ohernandezdev/flint` (renamed from `usbfrommac` earlier this session). All real links point there.
- Never commit secrets; this plan touches no GitHub Actions secrets.

---

### Task 1: Bring the approved visual assets into the repo

**Files:**
- Create: `docs/assets/iso-empty.png`
- Create: `docs/assets/windows-detected.png`
- Create: `docs/assets/choose-usb.png`
- Create: `docs/assets/confirm-erase.png`
- Create: `docs/assets/copy-progress.png`
- Create: `docs/assets/demo.gif`

**Interfaces:**
- Produces: the six PNG paths above (each 897x607, cropped, no border artifact) and one optimized GIF, all referenced by relative path from `docs/index.html` and `README.md`.

- [ ] **Step 1: Copy the cropped screenshots from scratchpad into the repo**

```bash
DIR=/private/tmp/claude-501/-Users-omarhernandez-Projects-Personal-Mac2Win11/8a63908a-3f09-4361-90c1-b2e23497866a/scratchpad/landing-assets
mkdir -p docs/assets
cp "$DIR/iso_empty_cropped.png" docs/assets/iso-empty.png
cp "$DIR/windows_detected_cropped.png" docs/assets/windows-detected.png
cp "$DIR/choose_usb_cropped.png" docs/assets/choose-usb.png
cp "$DIR/confirm_erase_cropped.png" docs/assets/confirm-erase.png
cp "$DIR/copy_progress_cropped.png" docs/assets/copy-progress.png
```

- [ ] **Step 2: Verify the 5 PNGs exist and are all 897x607**

Run: `file docs/assets/*.png`
Expected: each line reports `897 x 607`

- [ ] **Step 3: Re-encode the demo GIF at a smaller size for README embedding**

The raw capture (`~/Desktop/flint-demo-2026-07-14.gif`, 5.4MB, 800x542,
12fps, 45.5s) is too heavy for a README. Re-encode narrower and shorter
(first 20s covers ISO-select through confirm, the most useful part) with
the same palette two-pass approach used earlier this session:

```bash
SRC=~/Desktop/flint-demo-2026-07-14.gif
PALETTE=/tmp/palette_readme.png
ffmpeg -y -i "$SRC" -t 20 -vf "fps=10,scale=600:-1:flags=lanczos,palettegen" -update 1 -frames:v 1 "$PALETTE"
ffmpeg -y -i "$SRC" -i "$PALETTE" -t 20 -filter_complex "fps=10,scale=600:-1:flags=lanczos[x];[x][1:v]paletteuse" docs/assets/demo.gif
rm -f "$PALETTE"
ls -la docs/assets/demo.gif
```

Expected: `docs/assets/demo.gif` exists and is well under 2MB (600px wide,
10fps, 20s is roughly 1-1.5MB based on the original's bitrate).

- [ ] **Step 4: Commit**

```bash
git add docs/assets/
git commit -m "docs: add landing page and README screenshots/demo GIF"
```

---

### Task 2: Build the landing page (`docs/index.html`)

**Files:**
- Create: `docs/index.html`

**Interfaces:**
- Consumes: the 5 PNGs + app icon from Task 1 (referenced as `assets/*.png`,
  relative paths since this file lives in `docs/` alongside `assets/`).
- Produces: a standalone page GitHub Pages serves at
  `https://ohernandezdev.github.io/flint/`.

- [ ] **Step 1: Write `docs/index.html`**

Start from the approved artifact source
(`/private/tmp/claude-501/-Users-omarhernandez-Projects-Personal-Mac2Win11/8a63908a-3f09-4361-90c1-b2e23497866a/scratchpad/landing-assets/template.html`,
already approved by the user this session, no emoji, cropped screenshots,
line-SVG feature icons) and adapt it for the real repo:

1. Replace every embedded `data:image/png;base64,...` image `src` with a
   relative path to the Task 1 assets: hero image → `assets/windows-detected.png`;
   step cards → `assets/iso-empty.png`, `assets/choose-usb.png`,
   `assets/confirm-erase.png`, `assets/copy-progress.png`; nav/footer brand
   icon → reference `../App/Resources/Assets.xcassets/AppIcon.appiconset/icon_64.png`
   is NOT accessible from Pages (Xcode assets aren't shipped to `docs/`) —
   instead copy `App/Resources/Assets.xcassets/AppIcon.appiconset/icon_64.png`
   to `docs/assets/icon.png` (`cp App/Resources/Assets.xcassets/AppIcon.appiconset/icon_64.png docs/assets/icon.png`)
   and reference `assets/icon.png`.
2. Replace every placeholder `href="#"` on the two "Download for macOS"
   buttons with `https://github.com/ohernandezdev/flint/releases/latest`.
3. Replace the nav's `href="#"` GitHub link with
   `https://github.com/ohernandezdev/flint`.
4. Replace the footer's 4 placeholder `href="#"` links: GitHub →
   `https://github.com/ohernandezdev/flint`, License →
   `https://github.com/ohernandezdev/flint/blob/main/LICENSE`, Security
   policy → `https://github.com/ohernandezdev/flint/blob/main/SECURITY.md`,
   Contributing → `https://github.com/ohernandezdev/flint/blob/main/CONTRIBUTING.md`.
5. Insert the "Why I built this" callout between the closing `</header>`
   (end of Hero) and the `<section id="how">` opening tag:

```html
<div class="wrap">
  <div class="why-card">
    <p class="why-copy">I bought a new PC to build and needed a bootable
    Windows USB from a Mac. The choices were paying for one of the few
    macOS tools that do this, or trusting an unverified binary from a
    random site — for a tool that formats a disk and runs as root, neither
    sat right. There wasn't a free, open, and safe option, so I built the
    one I wanted. Writing it solo was realistic because most of the
    implementation happened alongside an AI coding agent — the kind of
    tool-assisted development that's only become practical the last couple
    of years.</p>
  </div>
</div>
```

Add matching CSS in the `<style>` block (near `.hero-shot`):

```css
.why-card {
  max-width: 640px; margin: 56px auto 0; padding: 20px 24px;
  border-left: 2px solid var(--link); background: var(--surface1);
  border-radius: 0 10px 10px 0;
}
.why-copy { font-size: 14.5px; color: var(--ink-muted); line-height: 1.65; margin: 0; }
```

6. Update the `<title>` if needed (keep as `Flint — Bootable USB creator
   for macOS`).
7. Save the result as `docs/index.html`.

- [ ] **Step 2: Verify it opens correctly as a local file**

Run: `open docs/index.html`
Expected: page renders in the default browser with all 5 screenshots and
the icon visible (no broken image icons), both CTA buttons point to the
real releases URL when hovered (check the status bar / right-click →
Copy Link), nav/footer links point to the real GitHub repo.

- [ ] **Step 3: Verify no emoji slipped in**

Run:
```bash
python3 -c "
import re
text = open('docs/index.html', encoding='utf-8').read()
matches = re.findall(r'[\U0001F300-\U0001FAFF]', text)
print('emoji found:', matches)
"
```
Expected: `emoji found: []`

- [ ] **Step 4: Verify dark mode looks intentional**

Run: `open docs/index.html`, then in the browser DevTools set
`prefers-color-scheme: dark` (or toggle macOS System Settings → Appearance
→ Dark, then reload).
Expected: background goes near-black, text goes near-white, the `.why-card`
left border and links use the dark-mode link blue (`#3291FF`), card shadows
are visibly darker/more diffuse — nothing reads as "inverted and broken."

- [ ] **Step 5: Add `.nojekyll` so GitHub Pages serves the file as-is**

Without this, GitHub Pages runs the whole `docs/` folder through Jekyll by
default, which is unnecessary for a single static HTML file and can add
build delay or, in rare cases involving underscore-prefixed paths, exclude
files.

```bash
touch docs/.nojekyll
```

- [ ] **Step 6: Commit**

```bash
git add docs/index.html docs/.nojekyll
git commit -m "feat: add GitHub Pages landing page"
```

---

### Task 3: Enable GitHub Pages for the repo

**Files:** none (repo settings only)

**Interfaces:**
- Consumes: `docs/index.html` from Task 2 must already be committed and
  pushed to `main` before this step, since GitHub Pages needs the folder
  to exist on the branch it's told to serve from.

- [ ] **Step 1: Push `main` first (Pages configuration reads from the remote branch)**

```bash
git push origin main
```

- [ ] **Step 2: Enable Pages via the GitHub API**

```bash
gh auth switch --hostname github.com --user ohernandezdev
gh api -X POST repos/ohernandezdev/flint/pages \
  -f "source[branch]=main" -f "source[path]=/docs" 2>&1
```

Expected: JSON response with `"status":"building"` or similar (a 201/409 —
409 means Pages was already enabled, which is also fine — re-run the
`PUT` variant below in that case: `gh api -X PUT repos/ohernandezdev/flint/pages -f "source[branch]=main" -f "source[path]=/docs"`).

- [ ] **Step 3: Confirm the Pages URL resolves (may take 1-2 minutes to build)**

```bash
sleep 60
curl -s -o /dev/null -w "%{http_code}\n" https://ohernandezdev.github.io/flint/
```
Expected: `200`. If it prints `404`, wait another minute and retry — first
Pages builds can take a few minutes.

- [ ] **Step 4: Restore the work gh account**

```bash
gh auth switch --hostname github.com --user ohernandez-dev-blossom
```

---

### Task 4: Refresh the README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: `docs/assets/demo.gif` from Task 1 (relative path from repo
  root: `docs/assets/demo.gif`).
- Produces: an updated README with a banner/GIF and a new "Why I built
  this" section other tasks don't depend on.

- [ ] **Step 1: Add a landing-page badge next to the existing badges**

In `README.md`, find the existing badge line block (starts with
`[![Platform: macOS 13+]...`) and add a 4th badge after the "Latest
release" one:

```markdown
[![Landing page](https://img.shields.io/badge/site-flint-171717.svg)](https://ohernandezdev.github.io/flint/)
```

- [ ] **Step 2: Insert the demo GIF right after the two intro paragraphs**

After the paragraph ending "...images are written raw, byte for byte, to
the device." and before `## Download`, insert:

```markdown
![Flint demo](docs/assets/demo.gif)
```

- [ ] **Step 3: Insert the "Why I built this" section**

Immediately after the demo GIF line (still before `## Download`), insert:

```markdown
## Why I built this

I bought a new PC to build and needed a bootable Windows USB from a Mac.
The choices were paying for one of the few macOS tools that do this, or
trusting an unverified binary from a random site — for a tool that formats
a disk and runs as root, neither sat right. There wasn't a free, open, and
safe option, so I built the one I wanted. Writing it solo was realistic
because most of the implementation happened alongside an AI coding agent —
the kind of tool-assisted development that's only become practical the
last couple of years.
```

- [ ] **Step 4: Add the new section to the Table of Contents**

In the `## Table of Contents` list, add `- [Why I built this](#why-i-built-this)`
right after `- [Download](#download)`.

- [ ] **Step 5: Verify the README renders correctly**

Run: `python3 -c "import markdown" 2>/dev/null && echo has-markdown || echo no-markdown-module`

If `has-markdown`: `python3 -c "import markdown; open('/tmp/readme_preview.html','w').write(markdown.markdown(open('README.md').read(), extensions=['fenced_code']))"` then `open /tmp/readme_preview.html` and confirm the GIF displays and the new section reads cleanly.

If `no-markdown-module`: just visually confirm in a text editor that the
inserted Markdown is syntactically correct (image line, `##` heading,
paragraph, ToC entry) — GitHub's own renderer is authoritative and this
is a simple enough diff that a syntax read-through is sufficient.

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs: add demo GIF, landing page link, and origin story to README"
```

---

### Task 5: Push everything

**Files:** none

- [ ] **Step 1: Push all commits from Tasks 1, 2, 4 (Task 3 already pushed)**

```bash
git push origin main
```

- [ ] **Step 2: Verify the live landing page and README**

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://ohernandezdev.github.io/flint/
open https://github.com/ohernandezdev/flint
```
Expected: `200`, and the GitHub repo page shows the new README banner/GIF
above the fold.
