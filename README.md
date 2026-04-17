# Optimizely Skills for Claude Code

A collection of [Claude Code skills](https://docs.claude.com/en/docs/claude-code/skills) that teach Claude how to work with the **Optimizely SaaS CMS** ecosystem — content modeling, Next.js integration, and frontend hosting.

Each skill is a self-contained folder with a `SKILL.md` entry point and supporting reference material that Claude loads on demand when the task matches.

## Included skills

| Skill | What it covers |
|---|---|
| [`optimizely-cms-content-types`](./optimizely-cms-content-types) | Authoring TypeScript content type definitions with `@optimizely/cms-sdk` — pages, blocks, elements, experiences, display templates, and the `optimizely.config.mjs` sync workflow. |
| [`optimizely-cms-nextjs`](./optimizely-cms-nextjs) | Wiring a Next.js 16 App Router app around the CMS SDK — GraphClient caching, locale middleware, revalidation webhooks, preview mode, Visual Builder rendering, and image handling. Heavily influenced by the code, docs and courses by Szymon Uryga (https://www.uryga.dev/) in addition to the public API docs. |
| [`optimizely-frontend-hosting`](./optimizely-frontend-hosting) | Packaging and deploying Next.js apps to Optimizely Frontend Hosting — environment configuration, deploy scripts, and the managed Test1/Test2/Production environments. |

The skills target **SaaS CMS** or **CMS 13 PaaS** — not CMS 12.

## Using these skills locally

Claude Code loads skills from two locations:

- **User-level** (available in every project): `~/.claude/skills/` — on Windows: `C:\Users\<you>\.claude\skills\`
- **Project-level** (available in one project): `<project>/.claude/skills/`

### 1. Get the files

```bash
git clone https://github.com/<your-fork>/skills.git
```

### 2. Make them available to Claude Code

Pick the option that matches where you want the skills to be available.

**Option A — Copy the skill folders**

Copy the individual skill folders into your target skills directory:

```bash
# user-level (all projects)
cp -r skills/optimizely-* ~/.claude/skills/

# or project-level (single project)
cp -r skills/optimizely-* /path/to/your-project/.claude/skills/
```

**Option B — Symlink / junction (stay in sync with `git pull`)**

Link the whole repo so updates flow through without re-copying.

Windows (run in an elevated `cmd` or with developer mode enabled):

```cmd
mklink /J "%USERPROFILE%\.claude\skills\optimizely-cms-content-types" "D:\Dev\skills\optimizely-cms-content-types"
mklink /J "%USERPROFILE%\.claude\skills\optimizely-cms-nextjs"        "D:\Dev\skills\optimizely-cms-nextjs"
mklink /J "%USERPROFILE%\.claude\skills\optimizely-frontend-hosting"  "D:\Dev\skills\optimizely-frontend-hosting"
```

macOS / Linux:

```bash
ln -s "$PWD/optimizely-cms-content-types"  ~/.claude/skills/optimizely-cms-content-types
ln -s "$PWD/optimizely-cms-nextjs"         ~/.claude/skills/optimizely-cms-nextjs
ln -s "$PWD/optimizely-frontend-hosting"   ~/.claude/skills/optimizely-frontend-hosting
```

### 3. Verify

Start Claude Code and run `/help` — the skills appear in the skill list once their folders are discoverable. Claude invokes them automatically when a request matches their description.
