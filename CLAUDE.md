# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hugo-based personal brand site and blog for Mohamed Shalan, deployed to GitHub Pages at https://moshalan.dev. It uses the PaperMod theme plus a custom "Two doors" homepage aimed at two audiences: people hiring a senior/lead mobile engineer, and engineering managers bringing AI agents into mobile teams (consulting).

Positioning line (used on the homepage, share card, title, and description): **"Senior mobile engineer helping teams adopt AI agents safely."**

## Development Commands

```bash
# Dev server (drafts included)
hugo server --buildDrafts --buildFuture

# Production build (same as CI)
HUGO_ENVIRONMENT=production HUGO_ENV=production hugo --gc --minify --baseURL "https://moshalan.dev/"

# Run the site verification suite (builds into a temp dir; never touches public/ or resources/)
bash tests/verify-site.sh            # all checks
bash tests/verify-site.sh urls og    # specific checks
node --test tests/                   # analytics unit tests (also run by the analytics check)
bash tests/verify-site.sh cutover   # gate: fails if resume, Cal.com or experience roles are unset or DRAFT copy remains (CI runs it)

# Regenerate the share card after changing the positioning line or avatar
bash scripts/make-og-card.sh

# Regenerate the public resume PDF after editing assets/resume/resume.html
bash scripts/make-resume.sh && bash tests/verify-site.sh resume

# New post
hugo new posts/my-new-post.md
```

## Architecture

### Theme
- **PaperMod** git submodule at `themes/PaperMod`, pinned to commit `1181196` (2026-10-25). Tag `v8.0` is from 2024 and predates the Hugo 0.158 floor, so the pin is a commit, not a tag.
- **Hugo Extended 0.169.0** locally and in CI. PaperMod requires >= 0.158.0.
- Initialize submodules: `git submodule update --init --recursive`

### Where things live
| What | File |
|---|---|
| Positioning line, email, LinkedIn, GitHub, Cal.com URL, resume PDF path | `hugo.toml` → `[params.brand]` |
| Homepage door copy + static proof items | `data/home.yaml` |
| Work with me headline, services, "Why me" numbers, "How it works" steps | `data/services.yaml` (sublead is the body of `content/work-with-me.md`) |
| Experience summary, roles timeline, skills | `data/experience.yaml` |
| Projects page cards | `data/projects.yaml` |
| Homepage layout | `layouts/home.html` + `layouts/_partials/brand/*.html` |
| Page layouts | `layouts/{work-with-me,experience,projects}.html` (chosen by `layout:` front matter) |
| Brand CSS (neutral, uses PaperMod color variables) | `assets/css/extended/brand.css` |
| PostHog, Mermaid loader, PWA links | `layouts/_partials/extend_head.html` |
| Share card source / output | `assets/og/card.html` → `static/images/og-default.png` |
| Public resume source / output | `assets/resume/resume.html` → `static/resume.pdf` (public data only: no phone, nationality, visa, or employer security findings; the `resume` check enforces it) |

Templates read data with `hugo.Data` (not the deprecated `site.Data`).

### Behaviors to keep
- **Work with me layout:** services are `<details>` rows (tap-to-open on phones; opened side by side at 720px+ by an inline script); a fixed booking bar (`.brand-sticky`) shows below 720px and lifts PaperMod's back-to-top button. The `work_with_me` check guards this.
- **Optional values hide their element.** `calcomURL` and `resumePDF` empty → their buttons don't render. Use `partial "brand/button.html" (dict "label" ... "url" ... "primary" bool)`, which renders nothing for an empty or `#` URL.
- **Case study:** the newest post with front matter `caseStudy: true` automatically appears in the homepage and Work with me proof rows. The case study never names the current employer (it's described, e.g. "a large delivery platform"). The Experience page names employers normally.
- **Cover images:** `cover.image: "images/<file>"` with **no leading slash**. Images live in `assets/images/`; a leading slash makes PaperMod skip publishing the image, so the cover and `og:image` 404.
- **Mermaid:** fenced ```mermaid blocks render through `layouts/_markup/render-codeblock-mermaid.html`. The script is loaded in `extend_head` when the page's raw markdown contains a mermaid block. (PaperMod caches the footer per page kind, so per-page flags don't work there.)
- **URLs:** `tests/baseline-urls.txt` lists every URL the pre-PaperMod site served. `check_urls` fails if any of them disappear. Never edit the baseline to make a check pass.

### Content
- Posts are Markdown with YAML front matter in `content/posts/`.
- `content/_index.md` holds the homepage alias `/page/1/` (kept from the old paginated homepage).

### Deployment
- GitHub Actions (`.github/workflows/hugo.yml`) deploys on push to `main`. It installs Hugo 0.169.0, runs `bash tests/verify-site.sh`, injects `POSTHOG_API_KEY` by replacing `apiKey = ""` in `hugo.toml` with `sed`, then builds with `--gc --minify`.
- Keep the literal `apiKey = ""` line in `hugo.toml`, otherwise the CI substitution silently does nothing.

### Analytics
PostHog config lives in `hugo.toml` under `[params.analytics.posthog]`. The snippet is in `layouts/_partials/extend_head.html` and only loads when an API key is set. Page views (`capture_pageview: true`) and page leaves are captured; session recording is off.

Custom events come from `assets/js/analytics.js` (loaded only when the API key is set; unit tests in `tests/analytics.test.mjs`, run by `node --test tests/` and by the `analytics` verify check):
- `cta_clicked` {cta, intent, location, link_url, link_text}. Links are classified by **where they point**, not by tags, so nav, theme social icons and links inside posts are covered: `/resume.pdf`, `/experience/`, LinkedIn `/in/` → `hiring`; `/work-with-me/`, cal.com, email on Work with me → `consulting`; GitHub, `/projects/`, other email → `other`. LinkedIn *share* links are ignored. `location` comes from the nearest known container (`home_doors`, `hero`, `nav`, `contact`, `proof`, `article_body`, ...).
- `service_expanded` {service, intent: consulting, location}: a Work with me service row tapped open on a phone (closing, and desktop's pre-opened rows, don't count).
- `article_progress` {article_path, title, reading_time_min, percent: 25|50|75|100, seconds} on posts.
- `article_read` {..., seconds}: reached the end of the post AND visible time >= 40% of Hugo's reading time.
- Post pages carry `<script id="article-meta">` JSON (path, title, readingTime) from `extend_head.html`.
- Scroll handling is throttled with a timer, not requestAnimationFrame (paused frames would stall it).

### PWA
`static/site.webmanifest` and the icons in `static/` are linked from `extend_head.html` and PaperMod's `[params.assets]`.

### Local AI Working Files (not in git)
Design specs, implementation plans, and mockups live in gitignored folders, so they exist only on the owner's machine. Search tools that respect `.gitignore` (ripgrep, Grep/Glob) will skip them, so list and read them directly:
- `docs/superpowers/specs/`: approved design documents (read before changing site structure or theme)
- `docs/superpowers/plans/`: implementation plans
- `.superpowers/`: brainstorming mockups, screenshots, execution ledgers

Never commit these folders.

### Development Notes
- `public/` and `resources/` are build output and are gitignored.
- Draft posts are excluded from production builds unless `--buildDrafts` is used.
