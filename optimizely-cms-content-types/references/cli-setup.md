# CMS CLI Setup (v2)

The `@optimizely/cms-cli` tool syncs content types to your Optimizely SaaS CMS instance.

## Installation

**Run without installing (recommended for one-offs):**
```bash
npx @optimizely/cms-cli@latest
```

**Install in a project:**
```bash
npm install @optimizely/cms-cli -D
npx optimizely-cms-cli
```

**Install globally:**
```bash
npm install @optimizely/cms-cli -g
optimizely-cms-cli
```

## Environment Variables

The CLI requires authentication credentials. Set these in `.env` (or `.env.local`):

```ini
OPTIMIZELY_CMS_CLIENT_ID=your-client-id
OPTIMIZELY_CMS_CLIENT_SECRET=your-client-secret
OPTIMIZELY_CMS_URL=https://your-instance.cms.optimizely.com
```

**For non-production environments** (cmstest, internal, local), override the API endpoint:

```ini
OPTIMIZELY_CMS_API_URL=https://api.cmstest.optimizely.com
```

The CLI defaults to `https://api.cms.optimizely.com`. The `OPTIMIZELY_CMS_API_URL` override is what most non-production setups need.

**Local CMS with self-signed certs:**
```ini
NODE_TLS_REJECT_UNAUTHORIZED="0"
```

> Never commit `.env` with secrets to version control.

## Creating optimizely.config.mjs

**CRITICAL:** The config file must use `components` with **file paths or globs as strings**. The CLI processes the files itself — do NOT import content types directly.

✅ **Correct — file paths and globs:**
```javascript
import { buildConfig } from '@optimizely/cms-sdk';

export default buildConfig({
  components: [
    // Single files
    './src/content-types/ArticlePage.ts',
    './src/content-types/HeroBlock.ts',

    // Or glob patterns
    './src/content-types/**/*.ts',
    './src/display-templates/**/*.ts',
  ],
  propertyGroups: [
    { key: 'content', displayName: 'Content', sortOrder: 1 },
    { key: 'seo', displayName: 'SEO', sortOrder: 2 },
    { key: 'settings', displayName: 'Settings', sortOrder: 3 },
  ],
});
```

❌ **Wrong — do NOT import objects directly:**
```javascript
// THIS WILL CAUSE "Cannot read properties of undefined (reading 'map')" ERROR
import { buildConfig } from '@optimizely/cms-sdk';
import { ButtonElementCT } from './src/content-types/ButtonElement.ts';

export default buildConfig({
  contentTypes: [ButtonElementCT],   // ❌ WRONG!
  displayTemplates: [...],            // ❌ WRONG!
});
```

**Key points:**
- Use `components` array with file path strings or glob patterns
- The CLI automatically discovers `contentType()` and `displayTemplate()` exports from these files
- Display templates in the same file as content types will be found automatically
- Property groups are defined inline in the config (not as file paths)

### Glob negation (exclude patterns)

Prefix a pattern with `!` to exclude matched files. Negation patterns must come *after* the inclusion patterns.

```javascript
export default buildConfig({
  components: [
    './src/content-types/**/*.ts',
    '!./src/content-types/internal/**',     // Exclude internal-only types
    '!./src/content-types/deprecated/**',   // Exclude deprecated types
    '!./src/content-types/_test.ts',        // Exclude a single file
  ],
});
```

Useful when you have content types in the same tree that shouldn't be pushed to CMS (test fixtures, internal-only types, layout components).

## Command Reference

| Command | Description |
|---------|-------------|
| `config push` | Push content types from your code to CMS |
| `config pull` | Pull content types from CMS and generate TypeScript files |
| `login` | Verify authentication with CMS |
| `content delete <key>` | Delete a specific content type from CMS |
| `danger delete-all-content-types` | Delete all user-defined content types (⚠️ destructive) |

### `config push`

Push your TypeScript content type definitions to Optimizely CMS. Reads `./optimizely.config.mjs` from the project root by default.

```bash
# Push with default config
npx @optimizely/cms-cli@latest config push

# Custom config path
npx @optimizely/cms-cli@latest config push --config ./custom-config.mjs

# Force update (overwrites existing types — may delete data if properties were removed)
npx @optimizely/cms-cli@latest config push --force

# Push against a specific CMS host (overrides OPTIMIZELY_CMS_URL)
npx @optimizely/cms-cli@latest config push --host https://example.cms.optimizely.com
```

**Flags:**
- `--config <path>` — Path to config file (default: `./optimizely.config.mjs`)
- `--force` — Force update; may result in data loss
- `--host <url>` — Override CMS host URL

> [!WARNING]
> `--force` overwrites existing content types in CMS. If your local definition removes properties, data in those properties will be lost.

### `config pull`

Pull content types from CMS and generate TypeScript files.

```bash
# Interactive (prompts for output dir + grouping)
npx @optimizely/cms-cli@latest config pull

# Explicit output directory
npx @optimizely/cms-cli@latest config pull --output ./src/content-types

# Group output by base type into page/, component/, section/, etc.
npx @optimizely/cms-cli@latest config pull --output ./src/content-types --group

# Output the manifest as JSON to stdout (good for piping / CI)
npx @optimizely/cms-cli@latest config pull --json
npx @optimizely/cms-cli@latest config pull > manifest.json
npx @optimizely/cms-cli@latest config pull | jq .contentTypes

# Include read-only system content types (otherwise excluded)
npx @optimizely/cms-cli@latest config pull --include-read-only
```

**Flags:**
- `--output <path>` — Output directory for generated files
- `--group` — Group files by base type (`page/`, `component/`, `section/`, `displayTemplates/`)
- `--json` — Output manifest JSON to stdout (auto-enabled when stdout is not a TTY)
- `--include-read-only` — Include read-only system content types (useful for PaaS/CMP-managed types)
- `--host <url>` — Override CMS host URL

**Output structure without `--group`:**
```
src/content-types/
├── ArticlePage.ts
├── ProductPage.ts
├── HeroComponent.ts
└── display-templates/
    ├── ArticleDisplayTemplate.ts
    └── HeroDisplayTemplate.ts
```

**With `--group`:**
```
src/content-types/
├── page/
│   ├── ArticlePage.ts
│   └── ProductPage.ts
├── component/
│   ├── HeroComponent.ts
│   └── Teaser.ts
├── section/
│   └── ContentSection.ts
└── displayTemplates/    # Only if orphaned templates exist
    └── LegacyTemplate.ts
```

### `login`

Verify your CMS credentials.

```bash
npx @optimizely/cms-cli@latest login

# Detailed output
npx @optimizely/cms-cli@latest login --verbose

# Test against specific instance
npx @optimizely/cms-cli@latest login --host https://example.cms.optimizely.com
```

Expected: `✓ Successfully authenticated with CMS`

### `content delete`

Delete a specific content type from CMS by key.

```bash
npx @optimizely/cms-cli@latest content delete ArticlePage
npx @optimizely/cms-cli@latest content delete ProductPage --host https://example.cms.optimizely.com
```

> [!WARNING]
> Deleting a content type also deletes all content instances of that type in CMS. Irreversible.

### `danger delete-all-content-types`

Deletes **all** user-defined content types from CMS. Requires interactive confirmation.

```bash
npx @optimizely/cms-cli@latest danger delete-all-content-types
```

> [!DANGER]
> Extremely destructive. Deletes every user-defined content type AND all content instances. Use only when intentionally resetting the CMS schema.

## Global Flags

Work with every command:
- `--help` — Show command help
- `--version` — Show CLI version

```bash
npx @optimizely/cms-cli@latest --help
npx @optimizely/cms-cli@latest config push --help
npx @optimizely/cms-cli@latest --version
```

## Common Workflows

### Initial setup
```bash
npx @optimizely/cms-cli@latest login                   # 1. Verify auth
npx @optimizely/cms-cli@latest config push             # 2. Push schema
# 3. Create content in CMS UI
```

### Sync schema changes
```bash
npx @optimizely/cms-cli@latest config push             # Normal update
npx @optimizely/cms-cli@latest config push --force     # If property types changed
```

### Pull existing schema (e.g. onboarding a new repo)
```bash
npx @optimizely/cms-cli@latest config pull --output ./src/content-types --group
```

### CI/CD
```bash
# Non-interactive — JSON output enabled automatically when stdout isn't a TTY
npx @optimizely/cms-cli@latest config push --config ./optimizely.config.mjs
npx @optimizely/cms-cli@latest config pull --json > manifest.json
```

## npm scripts (recommended)

Pin the major version in `package.json` so the CLI doesn't unexpectedly upgrade mid-project:

```json
{
  "scripts": {
    "cms:login": "npx @optimizely/cms-cli@^2.0.0 login",
    "cms:push-config": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs",
    "cms:push-config-force": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs --force",
    "cms:pull-config": "npx @optimizely/cms-cli@^2.0.0 config pull --output ./src/content-types --group"
  }
}
```

## Troubleshooting

**`Cannot read properties of undefined (reading 'map')`** — `optimizely.config.mjs` is using `contentTypes`/`displayTemplates` arrays instead of `components` with file paths. See the correct format above.

**`Failed to authenticate with CMS`** — Check `OPTIMIZELY_CMS_CLIENT_ID` and `OPTIMIZELY_CMS_CLIENT_SECRET`. Run `login --verbose` for details.

**`Failed to connect to CMS`** — Check `OPTIMIZELY_CMS_URL`. For non-prod environments set `OPTIMIZELY_CMS_API_URL`.

**`Config file not found`** — Ensure `optimizely.config.mjs` is in project root, or pass `--config ./path/to/config.mjs`.

**Push fails with "content type already exists with different properties"** — Review the diff between your local definition and CMS. Use `--force` only if you accept potential data loss.
