---
name: optimizely-cms-content-types
description: "Generate TypeScript content type definitions for Optimizely SaaS CMS using @optimizely/cms-sdk v1.0.0. Use when creating content types, TypeScript files for pages/blocks/elements/experiences, CMS content models, components like HeroBlock or CardBlock, page types like HomePage or ArticlePage, Visual Builder elements/sections, display templates, optimizely.config.mjs setup, CMS CLI sync, GraphClient fetching, damAssets usage, or React component rendering. Also trigger when the user mentions Optimizely SaaS CMS content modeling even without saying 'content types' — e.g. setting up pages, blocks, components, or Visual Builder. Do NOT use for CMS 12/PaaS (.NET types), Commerce catalog types, Graph queries, or frontend hosting (see optimizely-frontend-hosting skill)."
---

# Optimizely CMS Content Types

Generate TypeScript content type definitions for Optimizely SaaS CMS using the `contentType` function from `@optimizely/cms-sdk` v1.0.0.

**Key capabilities:**
- **Pages** (`_page`): HomePage, ArticlePage, BlogPage with unique URLs
- **Components** (`_component`): HeroBlock, BannerBlock, CardBlock — reusable blocks
- **Elements** (`_component` + `compositionBehaviors: ['elementEnabled']`): Smaller Visual Builder elements (title, button, image)
- **Sections** (`_section`): Visual Builder sections with layout system
- **Experiences** (`_experience`): Flexible visual page building
- **Composition**: Make components work as sections with `compositionBehaviors: ['sectionEnabled']`
- **Media types**: Custom image, video, media types
- **Folders** (`_folder`): Organize content in asset panel
- **GraphClient**: Fetch content from Optimizely Graph
- **damAssets**: DAM asset helpers (srcset, alt text, type guards)
- **React integration**: Server/client components for rendering

## Quick Start

### Basic Article Page

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const ArticlePageCT = contentType({
  key: 'ArticlePage',
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

### Component with Section Behavior

```typescript
export const HeroBlockCT = contentType({
  key: 'HeroBlock',
  displayName: 'Hero Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: {
    title: { type: 'string', displayName: 'Title' },
    subtitle: { type: 'string', displayName: 'Subtitle' },
  },
});
```

### Element (Simple Visual Builder Component)

```typescript
export const ButtonElementCT = contentType({
  key: 'ButtonElement',
  displayName: 'Button Element',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    text: { type: 'string', displayName: 'Button Text', required: true },
    link: { type: 'link', displayName: 'Link', required: true },
  },
});
```

## Built-in Content Metadata

**IMPORTANT**: All content types automatically include built-in metadata via `opti._metadata`. **DO NOT create redundant properties** for these fields.

Every content item has `_metadata` with these properties:

```typescript
opti._metadata.key               // Content unique key (string)
opti._metadata.locale             // Current locale (string)
opti._metadata.fallbackForLocale  // Fallback locale (string)
opti._metadata.version            // Version number (string)
opti._metadata.displayName        // Display name (string)
opti._metadata.url                // InferredUrl object
opti._metadata.types              // Array of type names (string[])
opti._metadata.published          // Published date (string) — use instead of creating publishDate
opti._metadata.status             // Content status (string)
opti._metadata.created            // Created date (string)
opti._metadata.lastModified       // Last modified date (string)
opti._metadata.sortOrder          // Sort order (number)
opti._metadata.variation          // Content variation (string)
```

**Instance-specific metadata** (pages/instances):
```typescript
opti._metadata.locales            // Available locales (string[])
opti._metadata.expired            // Expiration date (string | null)
opti._metadata.container          // Container path (string | null)
opti._metadata.owner              // Owner identifier (string | null)
opti._metadata.routeSegment       // URL route segment (string | null)
opti._metadata.path               // Content path (string[])
opti._metadata.lastModifiedBy     // Last modified by (string | null)
opti._metadata.createdBy          // Created by (string | null)
opti._metadata.changeset          // Changeset (string | null)
```

Other built-in properties:
```typescript
opti._id              // Unique content ID (string)
opti.__typename       // Content type name (string)
opti.__context?.edit  // Preview/edit mode flag (boolean)
```

❌ **DON'T create these redundant properties:**
```typescript
properties: {
  publishDate: { type: 'dateTime' },  // Use opti._metadata.published
  createdDate: { type: 'dateTime' },  // Use opti._metadata.created
  lastModified: { type: 'dateTime' }, // Use opti._metadata.lastModified
  title: { type: 'string' },          // Use opti._metadata.displayName (for system title)
}
```

Custom date properties are appropriate only for business-specific dates (event start/end, campaign dates, deadlines).

## Property Types

For the full property type reference with all options and examples, see `references/property-types.md`.

### Summary

| Type | Use For | Key Options |
|------|---------|-------------|
| `string` | Titles, names, short text | `minLength`, `maxLength`, `pattern`, `enum` |
| `richText` | Formatted content (Slate.js) | `localized` |
| `url` | Simple web address (InferredUrl at runtime) | — |
| `link` | Rich link with text, title, target | — |
| `boolean` | True/false checkboxes | — |
| `integer` | Whole numbers | `minimum`, `maximum` |
| `float` | Decimal values | `minimum`, `maximum` |
| `dateTime` | Date and time values | `minimum`, `maximum` (ISO format) |
| `array` | Lists of values (no nested arrays) | `items`, `minItems`, `maxItems` |
| `content` | Reference to content items (flexible) | `allowedTypes`, `restrictedTypes` |
| `contentReference` | Reference by ID (for media) | `allowedTypes` |
| `component` | Strongly-typed embedded component | `contentType` (CT reference) |
| `binary` | File attachments | — |
| `json` | Arbitrary JSON data | — |

### URL vs Link — Important Distinction

**`url`** stores a web address. At runtime, it resolves to an `InferredUrl` object (not a plain string).

**`link`** stores a rich link object with text, title, and target metadata.

```typescript
// Simple URL — resolves to InferredUrl at runtime
websiteUrl: { type: 'url', displayName: 'Website URL' }

// Rich link — resolves to { url: InferredUrl, text, title, target }
ctaLink: { type: 'link', displayName: 'Call to Action' }
```

**InferredUrl shape** (used by both `url` and `link`):
```typescript
{
  type: string | null;
  default: string | null;     // ← Use this for href values
  hierarchical: string | null;
  internal: string | null;
  graph: string | null;
  base: string | null;
}
```

**Link runtime shape** (what you receive in the component):
```typescript
{
  url: InferredUrl;    // URL as InferredUrl object — use url.default for href
  text: string | null; // Link display text
  title: string | null; // Tooltip / title attribute
  target: string | null; // e.g. '_blank'
}
```

### String Enums — Content Choices Only

Use `enum` only for semantic/content choices. For visual styling (colors, sizes, variants), use `displayTemplate` instead.

```typescript
// ✅ Correct: semantic content choice
headingLevel: {
  type: 'string',
  enum: [
    { value: 'h1', displayName: 'H1' },
    { value: 'h2', displayName: 'H2' },
    { value: 'h3', displayName: 'H3' },
  ],
}
```

## Property Configuration Options

All property types support these common options:

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

- **`'searchable'`** (default) — Fully indexed for full-text search
- **`'queryable'`** — Can be filtered/sorted but not full-text searched
- **`'disabled'`** — Not indexed at all

## Content Relationships

### AllowedTypes & RestrictedTypes

```typescript
featuredImage: {
  type: 'contentReference',
  allowedTypes: ['_image'],       // Whitelist
}

relatedContent: {
  type: 'content',
  restrictedTypes: ['_folder'],   // Blacklist
}
```

Options for both: specific content types (`[ArticleCT]`), base types (`['_page']`), self-reference (`['_self']`).

### MayContainTypes

Defines which content types can be created as children. Applies to `_page`, `_experience`, `_folder`, and `_component` base types.

```typescript
export const BlogPageCT = contentType({
  key: 'BlogPage',
  baseType: '_page',
  mayContainTypes: [ArticleCT, '_page', '_self', '*'],
  properties: { /* ... */ },
});
```

## CompositionBehaviors

Make components usable as sections in Visual Builder:

```typescript
export const CardBlockCT = contentType({
  key: 'CardBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: { /* ... */ },
});
```

- `'sectionEnabled'` — Can be used as a section in Visual Builder
- `'elementEnabled'` — Can be used as an element inside an Experience composition (columns/rows). This is the correct way to define elements. Per the official docs: https://github.com/episerver/content-js-sdk/blob/main/docs/8-experience.md

```typescript
export const ButtonElementCT = contentType({
  key: 'ButtonElement',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: { /* ... */ },
});
```

Both behaviors can coexist (`['sectionEnabled', 'elementEnabled']`) on a single content type if it should work as both a section and an element.

## Base Types

| Base Type | Description | Use For |
|-----------|-------------|---------|
| `_page` | Pages with unique URLs | HomePage, ArticlePage, BlogPage |
| `_component` | Reusable blocks/components (also elements via `elementEnabled`) | HeroBlock, CardBlock, ButtonElement, TitleElement |
| `_section` | Visual Builder sections with layout | Custom sections |
| `_experience` | Flexible visual page building | Dynamic experiences |
| `_folder` | Organizing content | Asset panel organization |
| `_image` | Image media types | Custom image types |
| `_video` | Video media types | Custom video types |
| `_media` | Generic media types | Documents, files |

### Elements vs Blocks (both use `_component`)

Elements and blocks share the same `_component` base type. The difference is which `compositionBehaviors` the content type declares:

- **Block only** — plain `_component` with no composition behaviors, or just `['sectionEnabled']`.
- **Element** — `_component` + `compositionBehaviors: ['elementEnabled']`. Makes it placeable inside a Visual Builder column/row.
- **Both** — `compositionBehaviors: ['sectionEnabled', 'elementEnabled']`.

Elements are meant to be simple, atomic units (button, title, image, text). Blocks are larger composite components. This is a semantic distinction, not a type-system one.

**Element property restrictions** — These property types are unreliable or forbidden on content types with `elementEnabled`:
- `content` (inline content property)
- `component` (inline strongly-typed component)
- `json`
- Arrays of content items (`type: 'array'` with `items: { type: 'content' }`)

**Safe property types on elements**: `string`, `boolean`, `integer`, `float`, `dateTime`, `url`, `richText`, `link`, `contentReference` (for media), and arrays of simple scalars.

> If a `_component` should work as both a block and an element, design its properties to respect the element restrictions — e.g. use fixed individual `link` properties (`primaryCta`, `secondaryCta`) instead of an array of content CTAs.

## Built-in Content Types

The SDK provides ready-to-use types:

```typescript
import { BlankExperienceContentType, BlankSectionContentType } from '@optimizely/cms-sdk';
```

Do not create a new type called `BlankExperience` — it already exists in the CMS.

## Type Inference with ContentProps

Use `ContentProps` to infer TypeScript types from content type definitions:

```typescript
import { ContentProps } from '@optimizely/cms-sdk';

type ArticleProps = ContentProps<typeof ArticlePageCT>;
// ArticleProps has typed fields: heading, body, _metadata, etc.
```

Works for content types and display templates:

```typescript
type ButtonSettings = ContentProps<typeof ButtonDisplayTemplate>;
// ButtonSettings has typed fields like: style, size
```

## Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Content type key | PascalCase | `HeroBlock`, `ArticlePage` |
| Export name | PascalCase + "CT" suffix | `HeroBlockCT`, `ArticlePageCT` |
| Display name | Friendly with spaces | `Hero Block`, `Article Page` |
| Property keys | camelCase | `heading`, `ctaUrl`, `backgroundImage` |
| File names | Match content type key | `HeroBlock.ts`, `ArticlePage.ts` |

## Property Groups

Organize properties in the CMS editor by assigning a `group` key.

Define groups in `optimizely.config.mjs`:

```javascript
propertyGroups: [
  { key: 'content', displayName: 'Content', sortOrder: 1 },
  { key: 'seo', displayName: 'SEO', sortOrder: 2 },
  { key: 'settings', displayName: 'Settings', sortOrder: 3 },
],
```

Then use in properties: `group: 'seo'`

**Built-in groups** (always available): `Information`, `Scheduling`, `Advanced`, `Shortcut`, `Categories`, `DynamicBlocks`. Note: the built-in `Advanced` group is displayed as "Settings" in the CMS UI.

## Display Templates

Use `displayTemplate` for visual styling options instead of enum properties on content types.

| Use `displayTemplate` | Use `enum` property |
|----------------------|---------------------|
| Button style (primary/secondary) | Heading level (h1-h6) |
| Colors and sizes | Content category |
| Layout alignment | Status values |
| Component variants | Semantic choices |

**Rule:** If it affects *how something looks*, use `displayTemplate`. If it affects *what something means*, use `enum`.

### Example

```typescript
import { contentType, displayTemplate, ContentProps } from '@optimizely/cms-sdk';

// Content type — NO visual styling properties
export const ButtonElementCT = contentType({
  key: 'ButtonElement',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    text: { type: 'string', displayName: 'Button Text', required: true },
    link: { type: 'link', displayName: 'Link', required: true },
  },
});

// Display template — defines visual variations
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
  opti: ContentProps<typeof ButtonElementCT>;
  displaySettings?: ContentProps<typeof ButtonDisplayTemplate>;
};

export default function ButtonElement({ opti, displaySettings }: Props) {
  const style = displaySettings?.style ?? 'primary';
  return <Button variant={style}>{opti.text}</Button>;
}
```

See `references/standard-types.md` for more display template examples.

## GraphClient — Fetching Content

```typescript
import { GraphClient } from '@optimizely/cms-sdk';

const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
  graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
});

// Fetch content by URL path
const content = await client.getContentByPath('/about-us/');

// Fetch with variation filtering
const content = await client.getContentByPath('/products/', {
  variation: { name: 'experiment1', value: 'variant-a' },
});

// Get breadcrumb/ancestor path
const ancestors = await client.getPath('/blog/my-article/');

// Get child pages
const children = await client.getItems('/blog/');

// Preview content (in preview route)
const preview = await client.getPreviewContent(previewParams);
```

See `references/graph-client.md` for full API reference.

## DAM Asset Helpers

```typescript
import { damAssets } from '@optimizely/cms-sdk';

export default function HeroBlock({ opti }) {
  const { getSrcset, getAlt, isDamImageAsset } = damAssets(opti);

  if (isDamImageAsset(opti.backgroundImage)) {
    return (
      <img
        src={opti.backgroundImage.item.Url}
        srcSet={getSrcset(opti.backgroundImage)}
        alt={getAlt(opti.backgroundImage, 'Hero')}
      />
    );
  }
}
```

See `references/dam-assets.md` for full API reference.

## React Integration

### Server Components (`@optimizely/cms-sdk/react/server`)

```typescript
import {
  initReactComponentRegistry,
  OptimizelyComponent,
  OptimizelyComposition,
  OptimizelyGridSection,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';
```

### Client Components (`@optimizely/cms-sdk/react/client`)

```typescript
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
```

See `references/react-integration.md` for full setup and usage.

## Best Practices

1. **Check built-in metadata first** — Use `opti._metadata.published`, `.created`, etc. instead of creating redundant date/title properties
2. **Use camelCase for property keys** — Follow SDK conventions
3. **Always add displayName** — Makes the CMS editor user-friendly
4. **Export with "CT" suffix** — e.g., `HeroBlockCT`, `ArticlePageCT`
5. **Distinguish url vs link** — `url` for simple URLs, `link` for rich links with text/title/target
6. **Use displayTemplate for visual styling** — Don't put colors, sizes, or layout variants in content type enum properties
7. **Use `_component` + `compositionBehaviors: ['elementEnabled']` for Visual Builder elements** — Button, Title, Image, etc. Per official docs: https://github.com/episerver/content-js-sdk/blob/main/docs/8-experience.md
8. **Respect element property restrictions** — On any `_component` with `elementEnabled`, avoid `content`, `component`, `json`, and arrays of content items
9. **No nested arrays** — Arrays cannot contain array items
10. **Config uses file paths** — `optimizely.config.mjs` must use `components` with string paths, not imported objects
11. **Use `ContentProps<typeof X>`** — For type-safe component props inferred from content types
12. **Use `damAssets()` for media** — Handles srcset, alt text, preview tokens automatically

## CMS CLI & Syncing

See `references/cli-setup.md` for full CLI documentation including installation, `optimizely.config.mjs` setup, and sync commands.

Quick reference:
```bash
npx optimizely-cms-cli config push optimizely.config.mjs   # Push to CMS
npx optimizely-cms-cli config pull                          # Pull from CMS
```

## Visual Builder Preview

See `references/visual-builder-preview.md` for preview route setup, SDK registry initialization, and required environment variables.

## References

- `references/property-types.md` — Complete property type reference with all options
- `references/standard-types.md` — Ready-to-use page, block, and element examples
- `references/validation.md` — Validation patterns and regex examples
- `references/composition-patterns.md` — Advanced composition and Visual Builder grid patterns
- `references/troubleshooting.md` — Common errors and solutions
- `references/cli-setup.md` — CMS CLI installation, config, and sync commands
- `references/visual-builder-preview.md` — Visual Builder preview route and SDK registry setup
- `references/graph-client.md` — GraphClient API for fetching content
- `references/dam-assets.md` — DAM asset helpers (srcset, alt, type guards)
- `references/react-integration.md` — React server/client component setup
- [CMS CLI Installation Guide](https://github.com/episerver/content-js-sdk/blob/main/docs/1-installation.md) — Official CLI documentation
