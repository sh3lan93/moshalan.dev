# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Hugo-based personal development blog for Mohamed Shalan, deployed to GitHub Pages. The site uses the LoveIt theme and focuses on software engineering content, particularly mobile development and Android/Flutter topics.

## Development Commands

### Local Development
```bash
# Start the development server with drafts enabled
hugo server --buildDrafts --buildFuture

# Start development server (production-like)
hugo server

# Build the site for production
hugo --gc --minify

# Create a new post
hugo new posts/my-new-post.md

# Create content using archetype
hugo new posts/my-post.md --kind posts
```

### Content Management
```bash
# Create new blog post
hugo new posts/title-of-post.md

# Create new page
hugo new about.md
```

### Build and Deployment
```bash
# Production build (same as CI)
HUGO_ENVIRONMENT=production HUGO_ENV=production hugo --gc --minify --baseURL "https://moshalan.dev/"

# Clean build artifacts
rm -rf public/ resources/
```

## Architecture

### Directory Structure
- `content/` - All markdown content files
  - `posts/` - Blog posts (created via `hugo new posts/`)
  - `about.md` - About page
- `themes/LoveIt/` - Git submodule containing the LoveIt theme
- `static/` - Static assets (images, favicons, etc.)
- `layouts/` - Custom layout overrides for the theme
- `archetypes/` - Content templates for `hugo new` command
- `public/` - Generated static site (git-ignored)
- `resources/` - Hugo processing cache (git-ignored)

### Configuration
- `hugo.toml` - Main Hugo configuration with theme settings, menu structure, and LoveIt theme parameters
- `.github/workflows/hugo.yml` - GitHub Actions workflow for automated deployment to GitHub Pages
- `themes/LoveIt` - Theme submodule (commit reference tracked in git)

### Theme Integration
The site uses the LoveIt theme (v0.3.0) as a git submodule. Theme customization is done through:
- Configuration in `hugo.toml` under `[params]` sections
- Custom layouts in `layouts/` directory (overrides theme defaults)
- Static assets in `static/` directory

### Progressive Web App (PWA) Support
The site includes comprehensive PWA capabilities:
- `static/site.webmanifest` - Web App Manifest with app shortcuts and metadata
- Multiple icon sizes for all platforms (16x16 to 512x512)
- Apple touch icons for iOS devices (120x120 to 180x180)
- Optimized for "Add to Home Screen" functionality
- Standalone display mode for app-like experience

### Content Structure
- Posts are written in Markdown with TOML frontmatter
- Default archetype includes date, draft status, and title
- Content supports Hugo's extended markdown features
- Theme provides built-in search, social sharing, and code highlighting

### Deployment
- Automatic deployment via GitHub Actions on push to `main` branch
- Uses Hugo Extended v0.128.0 in CI environment
- Builds with `--gc --minify` for optimization
- Deploys to GitHub Pages at https://moshalan.dev

### Analytics
The site uses PostHog for analytics and user behavior tracking:
- Configuration in `hugo.toml` under `[params.analytics.posthog]`
- Custom head partial at `layouts/partials/head/custom.html` adds PostHog script
- Add your PostHog API key to `params.analytics.posthog.apiKey` in `hugo.toml`
- Features: autocapture, pageview tracking, and optional session recording

### Development Notes
- Hugo Extended is required (for SCSS processing)
- Theme submodule must be initialized: `git submodule update --init --recursive`
- Draft posts are excluded from production builds unless `--buildDrafts` is used
- The site is configured for a mobile software engineering audience with appropriate SEO keywords