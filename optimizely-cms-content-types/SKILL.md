---
name: optimizely-cms-content-types
description: "Generate TypeScript content type definitions for Optimizely SaaS CMS using the Content JS SDK (@optimizely/cms-sdk). Use when the user requests: (1) Creating Optimizely content types, (2) Generating TypeScript files for pages/blocks/elements/experiences, (3) Setting up CMS content models, (4) Creating components like HeroBlock, BannerBlock, CardBlock, (5) Defining page types like HomePage, ArticlePage, BlogPage, (6) Creating elements or sections for Visual Builder, or (7) Making blocks that work as both blocks and elements using compositionBehaviors. Based on official SDK documentation and source code."
---

# Optimizely CMS Content Types

Generate TypeScript content type definitions for Optimizely SaaS CMS using the Content JS SDK.

## Overview

Create properly structured content type definitions for Optimizely SaaS CMS using the `contentType` function from `@optimizely/cms-sdk`.

**Key capabilities:**
- **Pages** (`_page`): HomePage, ArticlePage, BlogPage with unique URLs
- **Components** (`_component`): HeroBlock, BannerBlock, CardBlock - reusable blocks
- **Sections** (`_section`): Visual Builder sections with layout system
- **Elements** (`_component` + `elementEnabled`): Smaller Visual Builder elements (use `_component` base type with `compositionBehaviors: ['elementEnabled']`)
- **Experiences** (`_experience`): Flexible visual page building
- **Composition**: Make components work as sections/elements with `compositionBehaviors`
- **Media types**: Custom image, video, media types
- **Folders** (`_folder`): Organize content in asset panel

## Quick Start

### Basic Article Page

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const ArticleContentType = contentType({
  key: 'Article',
  baseType: '_page',
  properties: {
    heading: {
      type: 'string',
      displayName: 'Article Heading',
      group: 'content',
      indexingType: 'searchable',
    },
    body: {
      type: 'richText',
      displayName: 'Article Body',
      group: 'content',
    },
  },
});
```

### Component with Composition Behaviors

```typescript
export const HeroBlockCT = contentType({
  key: 'HeroBlock',
  displayName: 'Hero Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],  // Can be used as section
  properties: {
    title: { type: 'string', displayName: 'Title' },
    subtitle: { type: 'string', displayName: 'Subtitle' },
  },
});
```

## Built-in Content Metadata

**IMPORTANT**: All content types automatically include built-in metadata properties via `opti._metadata`. **DO NOT create redundant properties** for these fields.

### Available Metadata Properties

Every content item has `_metadata` with the following properties:

```typescript
opti._metadata.key           // Content unique key (string)
opti._metadata.locale        // Current locale (string)
opti._metadata.version       // Version number (string)
opti._metadata.displayName   // Display name (string)
opti._metadata.url           // InferredUrl object
opti._metadata.types         // Array of type names (string[])
opti._metadata.published     // Published date (string) ✅ Use instead of creating publishDate
opti._metadata.status        // Content status (string)
opti._metadata.created       // Created date (string)
opti._metadata.lastModified  // Last modified date (string)
opti._metadata.sortOrder     // Sort order (number)
opti._metadata.variation     // Variation name (string)
```

**Instance-specific metadata** (available on pages/instances):
```typescript
opti._metadata.locales       // Available locales (string[])
opti._metadata.expired       // Expiration date (string | null)
opti._metadata.container     // Container path (string | null)
opti._metadata.owner         // Owner identifier (string | null)
opti._metadata.routeSegment  // URL route segment (string | null)
opti._metadata.lastModifiedBy // Last modifier (string | null)
opti._metadata.path          // Content path (string[])
opti._metadata.createdBy     // Creator identifier (string | null)
```

### Common Mistakes to Avoid

❌ **DON'T create these redundant properties:**
```typescript
properties: {
  publishDate: { type: 'dateTime' },  // ❌ Use opti._metadata.published instead
  createdDate: { type: 'dateTime' },  // ❌ Use opti._metadata.created instead
  lastModified: { type: 'dateTime' }, // ❌ Use opti._metadata.lastModified instead
  title: { type: 'string' },          // ❌ Use opti._metadata.displayName instead (for system title)
}
```

✅ **DO use built-in metadata:**
```typescript
// In your component
export default function NewsPage({ opti }: Props) {
  const publishedDate = opti._metadata.published;
  const createdDate = opti._metadata.created;
  const pageTitle = opti._metadata.displayName;

  return (
    <article>
      <time dateTime={publishedDate}>{new Date(publishedDate).toLocaleDateString()}</time>
    </article>
  );
}
```

**When to create custom date properties:**
- Event start/end dates
- Custom scheduling fields
- Business-specific dates that differ from content lifecycle dates

### Other Built-in Properties

```typescript
opti._id              // Unique content ID (string)
opti.__typename       // Content type name (string)
opti.__context?.edit  // Preview/edit mode flag (boolean)
```

## Property Types

### String
Simple text fields for titles, names, short text.

```typescript
title: {
  type: 'string',
  displayName: 'Title',
  minLength: 5,
  maxLength: 100,
  pattern: '^[A-Za-z0-9 ]+$',
}
```

**Enum for content/semantic choices** (NOT for visual styling):
```typescript
// ✅ Correct: semantic content choice
headingLevel: {
  type: 'string',
  displayName: 'Heading Level',
  enum: [
    { value: 'h1', displayName: 'H1' },
    { value: 'h2', displayName: 'H2' },
    { value: 'h3', displayName: 'H3' },
  ],
}

// ❌ Wrong: visual styling - use displayTemplate instead
// style: { type: 'string', enum: [{ value: 'primary' }, { value: 'secondary' }] }
```

> **Important:** For visual styling options (colors, sizes, alignment, variants), use `displayTemplate` instead of enum properties. See the Display Templates section.

### Rich Text
Formatted content with rich text editing (Slate.js format).

```typescript
body: {
  type: 'richText',
  displayName: 'Article Body',
  localized: true,
}
```

### URL vs Link

**IMPORTANT DISTINCTION:**

**URL Property** - For simple web addresses as strings:
```typescript
websiteUrl: {
  type: 'url',
  displayName: 'Website URL',
  description: 'External website link',
}
```

**Link Property** - For rich link objects with all `<a>` tag attributes (text, title, target):
```typescript
ctaLink: {
  type: 'link',
  displayName: 'Call to Action Link',
  description: 'Link with title and target options',
}
```

**Key difference:** Use `url` for simple URL storage, use `link` when you need text, title, and target attributes.

### Boolean
True/false checkbox.

```typescript
isPublished: {
  type: 'boolean',
  displayName: 'Published',
}
```

### Integer & Float
Whole numbers or decimal values.

```typescript
quantity: {
  type: 'integer',
  displayName: 'Quantity',
  minimum: 1,
  maximum: 100,
}

price: {
  type: 'float',
  displayName: 'Price',
  minimum: 0.01,
  maximum: 99999.99,
}
```

### DateTime
Date and time values with optional constraints.

```typescript
publishDate: {
  type: 'dateTime',
  displayName: 'Publish Date',
  required: true,
}

eventStartTime: {
  type: 'dateTime',
  displayName: 'Event Start',
  minimum: '2025-12-01T00:00:00Z',  // ISO format
  maximum: '2025-12-31T23:59:59Z',
}
```

### Array
Lists of values. **Cannot contain nested arrays.**

```typescript
tags: {
  type: 'array',
  displayName: 'Tags',
  items: { type: 'string' },
  minItems: 1,
  maxItems: 10,
}

relatedArticles: {
  type: 'array',
  displayName: 'Related Articles',
  items: {
    type: 'content',
    allowedTypes: ['ArticlePage'],
  },
}
```

### Content & ContentReference
Reference to other content items.

```typescript
featuredImage: {
  type: 'contentReference',
  displayName: 'Featured Image',
  allowedTypes: ['_image'],
}

heroSection: {
  type: 'content',
  displayName: 'Hero Section',
  allowedTypes: ['HeroBlock'],
  restrictedTypes: ['_folder'],
}
```

### Component
Embed a specific component type (strongly typed).

```typescript
import { HeroBlockCT } from './HeroBlock';

hero: {
  type: 'component',
  contentType: HeroBlockCT,
  displayName: 'Hero Section',
}
```

### Binary & JSON
```typescript
attachment: { type: 'binary', displayName: 'File' }
metadata: { type: 'json', displayName: 'Metadata' }
```

## Property Configuration Options

### Common Options

```typescript
{
  displayName: 'Field Label',      // Shown in CMS UI
  description: 'Help text',        // Tooltip
  required: true,                  // Must have value
  localized: true,                 // Different per language
  group: 'content',                // Property group
  sortOrder: 10,                   // Display order
  indexingType: 'searchable',      // Search configuration
}
```

### Indexing Types

Controls how properties are indexed for search. **Default is 'searchable'.**

- **`'searchable'`** (default) - Fully indexed for full-text search
- **`'queryable'`** - Can be filtered/sorted but not full-text searched
- **`'disabled'`** - Not indexed at all

```typescript
properties: {
  title: {
    type: 'string',
    indexingType: 'searchable',   // Full-text search
  },
  publishDate: {
    type: 'dateTime',
    indexingType: 'queryable',    // Filter/sort only
  },
  internalNotes: {
    type: 'string',
    indexingType: 'disabled',     // Not searchable
  },
}
```

## Content Relationships

### AllowedTypes & RestrictedTypes

Control which content types can be referenced:

```typescript
featuredArticle: {
  type: 'content',
  allowedTypes: [ArticleCT],  // Only allow Article
}

relatedContent: {
  type: 'content',
  restrictedTypes: ['_folder'],  // Allow all except folders
}
```

**AllowedTypes** - Whitelist that can include:
- Specific content types: `[ArticleCT, VideoCT]`
- Base types: `['_page', '_component']`
- Self-reference: `['_self']`

**RestrictedTypes** - Blacklist using same format

## MayContainTypes

Defines which content types can be created as children. Applies to `_page`, `_experience`, and `_folder` base types.

```typescript
export const BlogPageCT = contentType({
  key: 'BlogPage',
  baseType: '_page',
  mayContainTypes: [
    ArticleCT,
    '_page',     // All page types
    '_self',     // Same type (BlogPage)
    '*',         // Wildcard: allow all types
  ],
  properties: { /* ... */ },
});
```

**Options:**
- Specific types: `[ArticleCT]`
- Base types: `['_page', '_component']`
- Self-reference: `['_self']`
- **Wildcard: `['*']`** - Allow all types

## CompositionBehaviors

Make components usable in Visual Builder:

```typescript
export const CardBlockCT = contentType({
  key: 'CardBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled', 'elementEnabled'],  // Flexible!
  properties: { /* ... */ },
});
```

**Options:**
- `'sectionEnabled'` - Can be used as a section
- `'elementEnabled'` - Can be used as an element
- Both - Maximum flexibility

**⚠️ IMPORTANT RESTRICTIONS for `elementEnabled`**:

Content types with `elementEnabled` in `compositionBehaviors` have the following restrictions. **Elements are meant to be simple, atomic components, not containers.**

**FORBIDDEN property types with `elementEnabled`:**
1. ❌ Arrays with content: `type: "array"` with `items: { type: "content" }`
2. ❌ Content properties: `type: "content"`
3. ❌ Component properties: `type: "component"`
4. ❌ JSON properties: `type: "json"`

**ALLOWED property types with `elementEnabled`:**
- ✅ Simple types: `string`, `boolean`, `integer`, `float`, `dateTime`, `url`, `richText`
- ✅ Content references: `type: "contentReference"` (for images, media)
- ✅ Arrays of simple types: `type: "array"` with `items: { type: "string" }` etc.

**When to use ONLY `sectionEnabled`** (remove `elementEnabled`):
- Component needs to contain other content blocks
- Component needs arrays of content items (like AccordionBlock with AccordionItems)
- Component needs JSON data structures
- Component acts as a container or has complex nested content

## Base Types

| Base Type | Description | Use For |
|-----------|-------------|---------|
| `_page` | Pages with unique URLs | HomePage, ArticlePage, BlogPage |
| `_component` | Reusable blocks/components | HeroBlock, CardBlock, and **elements** (with `elementEnabled`) |
| `_section` | Visual Builder sections with layout | Custom sections |
| `_experience` | Flexible visual page building | Dynamic experiences |
| `_folder` | Organizing content | Asset panel organization |
| `_image` | Image media types | Custom image types |
| `_video` | Video media types | Custom video types |
| `_media` | Generic media types | Documents, files |

> **Note:** There is no `_element` base type. Elements are `_component` types with `compositionBehaviors: ['elementEnabled']`.

## Built-in Content Types

The SDK provides ready-to-use types:

```typescript
import { BlankExperienceContentType, BlankSectionContentType } from '@optimizely/cms-sdk';
```

- **BlankExperienceContentType** - Experience with no predefined properties
- **BlankSectionContentType** - Section with no predefined properties

**Important!** Do not create a new type called `BlankExperience` as this is already defined in the CMS by default.

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Content type key | PascalCase | `HeroBlock`, `ArticlePage` |
| Export name | PascalCase + "CT" suffix | `HeroBlockCT`, `ArticlePageCT` |
| Display name | Friendly with spaces | `Hero Block`, `Article Page` |
| Property keys | camelCase | `heading`, `ctaUrl`, `backgroundImage` |
| Property display names | Friendly | `Heading`, `CTA URL`, `Background Image` |
| File names | Match content type key | `HeroBlock.tsx`, `ArticlePage.tsx` |

## Property Groups

Organize properties in the CMS editor.

### Define in Config

In `optimizely.config.mjs`:

```javascript
import { buildConfig } from '@optimizely/cms-sdk';

export default buildConfig({
  components: ['./src/components/**/*.tsx'],
  propertyGroups: [
    { key: 'content', displayName: 'Content', sortOrder: 1 },
    { key: 'seo', displayName: 'SEO', sortOrder: 2 },
    { key: 'styling', displayName: 'Styling', sortOrder: 3 },
  ],
});
```

### Use in Properties

```typescript
properties: {
  title: {
    type: 'string',
    displayName: 'Page Title',
    group: 'seo',  // Assigns to SEO group
  },
}
```

**Built-in groups** (always available):
- `Information`, `Scheduling`, `Advanced`, `Shortcut`, `Categories`, `DynamicBlocks`

**Note!** The built-in group `Advanced` is named "Settings" in the CMS UI.

## Common Patterns

See `references/standard-types.md` for complete examples:
- Page types: HomePage, ArticlePage, BlogPage, LandingPage
- Components: HeroBlock, BannerBlock, CallToActionBlock, CardBlock
- Elements: TitleElement, TextElement, ImageElement, ButtonElement

See `references/composition-patterns.md` for:
- Nested components
- Tab and accordion patterns
- Card grids
- Flexible content areas

## Display Templates

**IMPORTANT:** Use `displayTemplate` for visual styling options instead of enum properties on content types.

### When to Use Display Templates vs Enum Properties

| Use `displayTemplate` | Use `enum` property |
|----------------------|---------------------|
| Button style (primary/secondary) | Heading level (h1-h6) |
| Colors and sizes | Content category |
| Layout alignment | Status values |
| Component variants | Semantic choices |

**Rule:** If it affects *how something looks*, use `displayTemplate`. If it affects *what something means*, use `enum`.

### Basic Example

```typescript
import { contentType, displayTemplate, Infer } from '@optimizely/cms-sdk';

// Content type - NO visual styling properties
export const ButtonElementCT = contentType({
  key: 'ButtonElement',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    text: { type: 'string', displayName: 'Button Text', required: true },
    link: { type: 'link', displayName: 'Link', required: true },
  },
});

// Display template - defines visual variations
export const ButtonDisplayTemplate = displayTemplate({
  key: 'ButtonDisplayTemplate',
  isDefault: true,
  displayName: 'Button Style',
  contentType: 'ButtonElement',
  settings: {
    style: {
      editor: 'select',
      displayName: 'Style',
      sortOrder: 0,
      choices: {
        primary: { displayName: 'Primary', sortOrder: 1 },
        secondary: { displayName: 'Secondary', sortOrder: 2 },
      },
    },
  },
});
```

### Using in Components

```typescript
type Props = {
  opti: Infer<typeof ButtonElementCT>;
  displaySettings?: Infer<typeof ButtonDisplayTemplate>;
};

export default function ButtonElement({ opti, displaySettings }: Props) {
  const style = displaySettings?.style ?? 'primary';
  return <Button variant={style}>{opti.text}</Button>;
}
```

See `references/standard-types.md` for complete display template examples.

## Best Practices

1. **Check built-in metadata first** - Use `opti._metadata.published`, `opti._metadata.created`, etc. instead of creating redundant properties
2. **Use camelCase for property keys** - Follow SDK conventions
3. **Add displayName always** - Makes CMS user-friendly
4. **Export with "CT" suffix** - e.g., `HeroBlockCT`, `ArticlePageCT`
5. **Use indexingType appropriately** - Default is 'searchable'
6. **Distinguish url vs link** - Use `url` for simple URLs, `link` for rich links
7. **Enable localization** - Set `localized: true` for translatable content
8. **Use compositionBehaviors** - Make components flexible, but avoid `elementEnabled` with JSON/content properties
9. **Control with allowedTypes** - Prevent wrong content types
10. **Use wildcard cautiously** - `mayContainTypes: ['*']` allows all types
11. **No nested arrays** - Arrays cannot contain array items
12. **Use displayTemplate for styling** - Don't put visual options in content type enum properties

## Optimizely CMS CLI

The `@optimizely/cms-cli` tool is used to sync content types to your Optimizely SaaS CMS instance.

### Installation

**For a project (recommended):**
```bash
npm install @optimizely/cms-cli -D
```

**Global installation:**
```bash
npm install @optimizely/cms-cli -g
```

### Usage

Run the CLI using npx:
```bash
npx optimizely-cms-cli
```

### Environment Variables

The CLI requires authentication credentials to connect to your Optimizely SaaS CMS instance. Set these environment variables:

```bash
OPTIMIZELY_CMS_CLIENT_ID=your-client-id
OPTIMIZELY_CMS_CLIENT_SECRET=your-client-secret
```

Add these to your `.env` or `.env.local` file for local development.

### Creating optimizely.config.mjs

**CRITICAL:** The config file must use `components` with **file paths as strings**. The CLI processes the files itself - do NOT import content types directly.

✅ **Correct - use file paths:**
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

❌ **Wrong - do NOT import objects directly:**
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

### Sync Content Types to CMS

After defining content types, sync them to your CMS:

```bash
npx optimizely-cms-cli config push optimizely.config.mjs
```

### Common Commands

```bash
# Push content type configuration to CMS
npx optimizely-cms-cli config push optimizely.config.mjs

# Pull existing configuration from CMS
npx optimizely-cms-cli config pull

# View help and available commands
npx optimizely-cms-cli --help
```

## Visual Builder Preview Setup

For Visual Builder to work, you need three things:

### 1. SDK Registry Initialization

Create `src/optimizely.ts` and import it in your root layout:

```typescript
import {
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

// MUST include BlankExperienceContentType and BlankSectionContentType
initContentTypeRegistry([
  BlankExperienceContentType,
  BlankSectionContentType,
  // ... your content types
]);

initReactComponentRegistry({
  resolver: {
    BlankExperience,  // React component for experiences
    BlankSection,     // React component for sections
    // ... your components
  },
});
```

### 2. Experience Components

Create `BlankExperience` and `BlankSection` React components. See `references/troubleshooting.md` for complete examples.

### 3. Preview Route

Create `app/preview/page.tsx`:

```typescript
import { GraphClient, type PreviewParams } from '@optimizely/cms-sdk';
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
import Script from 'next/script';

export default async function PreviewPage({ searchParams }: Props) {
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
  });

  const response = await client.getPreviewContent(
    (await searchParams) as PreviewParams
  );

  return (
    <div>
      <Script
        src={`${process.env.OPTIMIZELY_CMS_URL}/util/javascript/communicationinjector.js`}
        strategy="afterInteractive"
      />
      <PreviewComponent />
      <OptimizelyComponent opti={response} />
    </div>
  );
}
```

### Required Environment Variables

```bash
OPTIMIZELY_CMS_URL=https://app-xxx.cms.optimizely.com
OPTIMIZELY_GRAPH_GATEWAY=https://cg.optimizely.com/content/v2  # Include full path!
OPTIMIZELY_GRAPH_SINGLE_KEY=your-single-key
```

## References

- `references/property-types.md` - Complete property type reference
- `references/standard-types.md` - Ready-to-use pages, blocks, elements
- `references/validation.md` - Validation patterns and regex
- `references/composition-patterns.md` - Advanced composition patterns
- `references/troubleshooting.md` - Common errors and solutions
- [CMS CLI Installation Guide](https://github.com/episerver/content-js-sdk/blob/main/docs/1-installation.md) - Official CLI documentation
