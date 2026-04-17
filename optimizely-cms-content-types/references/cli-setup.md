# CMS CLI Setup

The `@optimizely/cms-cli` tool syncs content types to your Optimizely SaaS CMS instance.

## Installation

**For a project (recommended):**
```bash
npm install @optimizely/cms-cli -D
```

**Global installation:**
```bash
npm install @optimizely/cms-cli -g
```

## Usage

Run the CLI using npx:
```bash
npx optimizely-cms-cli
```

## Environment Variables

The CLI requires authentication credentials. Set these environment variables:

```bash
OPTIMIZELY_CMS_CLIENT_ID=your-client-id
OPTIMIZELY_CMS_CLIENT_SECRET=your-client-secret
```

Add these to your `.env` or `.env.local` file for local development.

## Creating optimizely.config.mjs

**CRITICAL:** The config file must use `components` with **file paths as strings**. The CLI processes the files itself — do NOT import content types directly.

✅ **Correct — use file paths:**
```javascript
import { buildConfig } from '@optimizely/cms-sdk';

export default buildConfig({
  components: [
    // List each file containing content types or display templates
    './src/cms/content-types/elements/ButtonElement.ts',
    './src/cms/content-types/elements/NavLinkElement.ts',
    './src/cms/content-types/blocks/HeroBlock.ts',
    './src/cms/content-types/blocks/TextBlock.ts',
    './src/cms/content-types/pages/ArticlePage.ts',
    './src/cms/content-types/settings/HeaderSettings.ts',
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
import { ButtonElementCT } from './src/cms/content-types/elements/ButtonElement.ts';
import { HeroBlockCT } from './src/cms/content-types/blocks/HeroBlock.ts';

export default buildConfig({
  contentTypes: [ButtonElementCT, HeroBlockCT],  // ❌ WRONG!
  displayTemplates: [ButtonDisplayTemplate],      // ❌ WRONG!
});
```

**Key points:**
- Use `components` array with file path strings
- The CLI automatically discovers `contentType()` and `displayTemplate()` exports from these files
- Display templates in the same file as content types will be found automatically
- Property groups are defined inline in the config (not as file paths)

## Sync Content Types to CMS

After defining content types, sync them to your CMS:

```bash
npx optimizely-cms-cli config push optimizely.config.mjs
```

## Common Commands

```bash
# Push content type configuration to CMS
npx optimizely-cms-cli config push optimizely.config.mjs

# Pull existing configuration from CMS
npx optimizely-cms-cli config pull

# View help and available commands
npx optimizely-cms-cli --help
```
