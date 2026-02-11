# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **Claude Skills repository** containing reusable AI assistant skills for the **Optimizely SaaS CMS** ecosystem. Skills are linked into projects via `link-skills.cmd` which creates a junction at `.claude\skills` pointing here.

There are two independent skills that together cover the full headless CMS workflow: content modeling → frontend deployment.

## Skills

### optimizely-cms-content-types

Generates TypeScript content type definitions for Optimizely SaaS CMS using the Content JS SDK (`@optimizely/cms-sdk`). This targets **SaaS CMS only** — not CMS 12/PaaS.

- **Entry point**: `SKILL.md` — complete skill documentation with quick start examples
- **References**: `references/` contains detailed guides for property types, standard types, composition patterns, validation, and troubleshooting
- **Sync command**: `npx optimizely-cms-cli config push optimizely.config.mjs`

Key conventions:
- Content type keys: PascalCase (`HeroBlock`, `ArticlePage`)
- Export names: PascalCase + "CT" suffix (`HeroBlockCT`)
- Property keys: camelCase (`ctaLink`, `backgroundImage`)
- Files: Match content type key (`HeroBlock.tsx`)
- Base types: `_page`, `_component`, `_section`, `_experience`, `_folder`, `_image`, `_video`, `_media`
- Elements are `_component` with `compositionBehaviors: ['elementEnabled']`

Critical gotchas:
- `optimizely.config.mjs` must use file paths (strings), NOT imported objects
- Elements only support: string, richText, url, link, boolean, integer, float, dateTime, json — no contentReference, content, component, array, or binary
- Built-in metadata (publishDate, createdDate, lastModified, displayName) should NOT be redefined as properties

### optimizely-frontend-hosting

Configures and deploys Next.js applications to Optimizely Frontend Hosting.

- **Entry point**: `SKILL.md` — workflow decision tree for setup/deployment/configuration
- **References**: `references/` contains deployment guide, environment variables guide, and troubleshooting
- **Deploy script**: `scripts/deploy.ps1` (PowerShell 5.1+)
- **Templates**: `assets/` contains `.zipignore.template` and `package.json.template`

Key conventions:
- Managed environments: Test1, Test2, Production (SaaS) — NOT Integration/Preproduction (PaaS)
- Deployment ZIP filename must contain `.head.app.`
- `package.json` must be at ZIP root, not nested
- `.zipignore` must exclude `.next`, `node_modules`, `.env` files

Critical gotchas:
- `OPTIMIZELY_GRAPH_GATEWAY` at runtime is base URL only (`https://cg.optimizely.com`), but locally includes full path (`/content/v2`) — see helper function in SKILL.md
- Set environment variables in PaaS Portal BEFORE first deployment to avoid locked state
- ISR is not yet supported; only SSG and SSR
- Cannot upload duplicate package names unless content differs

## Linking Skills to Projects

```cmd
link-skills.cmd D:\Dev\myapp
```

Creates junction: `D:\Dev\myapp\.claude\skills` → this repository.
