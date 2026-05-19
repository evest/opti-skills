---
name: optimizely-cms-content-types
description: "Generate TypeScript content type definitions for Optimizely SaaS CMS using @optimizely/cms-sdk v2 and @optimizely/cms-cli v2. Use when creating content types, TypeScript files for pages/blocks/elements/experiences, CMS content models, components like HeroBlock or CardBlock, page types like HomePage or ArticlePage, Visual Builder elements/sections, display templates, optimizely.config.mjs setup, CMS CLI sync, DAM asset rendering, RichText rendering, or the React component pattern that consumes content types (ContentProps, getPreviewUtils, pa, src). Also trigger when the user mentions Optimizely SaaS CMS content modelling even without saying 'content types' — e.g. setting up pages, blocks, components, or Visual Builder. Do NOT use for CMS 12/PaaS (.NET types), Commerce catalog types, Optimizely Graph schema, or frontend hosting deployment (see optimizely-frontend-hosting skill). Defer detailed runtime/preview-route wiring (withAppContext, ISR, middleware, layout.tsx integration) to the optimizely-cms-nextjs skill."
---

# Optimizely CMS Content Types (SDK v2)

Generate TypeScript content type definitions for Optimizely SaaS CMS using the `contentType` and `displayTemplate` functions from `@optimizely/cms-sdk` v2.

**Key capabilities:**
- **Pages** (`_page`): HomePage, ArticlePage, BlogPage with unique URLs
- **Components** (`_component`): HeroBlock, BannerBlock, CardBlock — reusable blocks
- **Elements** (`_component` + `compositionBehaviors: ['elementEnabled']`): Smaller Visual Builder elements (title, button, image)
- **Sections** (`_section`): Visual Builder sections with layout system
- **Experiences** (`_experience`): Flexible visual page building
- **Composition**: Make components work as sections with `compositionBehaviors: ['sectionEnabled']`
- **Media types**: Custom image, video, media types
- **Folders** (`_folder`): Organize content in asset panel
- **Display templates**: Visual styling variants and grid (row/column) settings
- **damAssets**: DAM asset helpers (srcset, alt text, type guards)
- **React integration**: The component pattern (`ContentProps`, `getPreviewUtils`, `pa`, `src`) used to render registered types

## v2 in 30 seconds

If you've used SDK v1:
- **Recommended fetching pattern** is now `config({ apiKey, graphUrl, ... })` once at app entry + `getClient()` everywhere else, instead of `new GraphClient()` per call. `new GraphClient()` still works.
- **New** `client.getContent(reference)` method accepts a `GraphReference` object (`{ key, locale?, version? }`) or `graph://` string. `getPath`/`getItems` also accept these.
- **New** `withAppContext` HOC wraps your page/preview route to provide request-scoped context; `getContextData('preview_token' | 'locale' | 'key' | 'version' | 'mode')` reads from it. Detailed wiring belongs to the `optimizely-cms-nextjs` skill.
- **Canonical prop name** in v2 docs and the React component pattern is `content` (not `opti`). Pick one and stay consistent in a project.
- **CLI** ships under `@optimizely/cms-cli@latest` with new flags (`--group`, `--json`, `--include-read-only`, `--config`, `--host`) and new commands (`content delete`, `danger delete-all-content-types`). See `references/cli-setup.md`.

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

**IMPORTANT**: All content types automatically include built-in metadata via `content._metadata`. **DO NOT create redundant properties** for these fields.

Every content item has `_metadata` with these properties:

```typescript
content._metadata.key               // Content unique key (string)
content._metadata.locale            // Current locale (string)
content._metadata.fallbackForLocale // Fallback locale (string)
content._metadata.version           // Version number (string)
content._metadata.displayName       // Display name (string)
content._metadata.url               // InferredUrl object
content._metadata.types             // Array of type names (string[])
content._metadata.published         // Published date (string) — use instead of creating publishDate
content._metadata.status            // Content status (string)
content._metadata.created           // Created date (string)
content._metadata.lastModified      // Last modified date (string)
content._metadata.sortOrder         // Sort order (number)
content._metadata.variation         // Content variation (string)
```

**Instance-specific metadata** (pages/instances):
```typescript
content._metadata.locales           // Available locales (string[])
content._metadata.expired           // Expiration date (string | null)
content._metadata.container         // Container path (string | null)
content._metadata.owner             // Owner identifier (string | null)
content._metadata.routeSegment      // URL route segment (string | null)
content._metadata.path              // Content path (string[])
content._metadata.lastModifiedBy    // Last modified by (string | null)
content._metadata.createdBy         // Created by (string | null)
content._metadata.changeset         // Changeset (string | null)
```

Other built-in properties:
```typescript
content._id              // Unique content ID (string)
content.__typename       // Content type name (string)
content.__context?.edit  // Preview/edit mode flag (boolean)
```

❌ **DON'T create these redundant properties:**
```typescript
properties: {
  publishDate: { type: 'dateTime' },  // Use content._metadata.published
  createdDate: { type: 'dateTime' },  // Use content._metadata.created
  lastModified: { type: 'dateTime' }, // Use content._metadata.lastModified
  title: { type: 'string' },          // Use content._metadata.displayName (for system title)
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
  url: InferredUrl;     // URL as InferredUrl object — use url.default for href
  text: string | null;  // Link display text
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

> [!IMPORTANT]
> Always specify `allowedTypes` or `restrictedTypes` on `content` and `contentReference` properties (and on array items of those types). Without constraints, the SDK generates nested GraphQL fragments for every possible content type. SDK v2 emits a warning when a single fragment exceeds `maxFragmentThreshold` (default 100). The threshold is configurable via `config({ maxFragmentThreshold: 150 })` but raising it is rarely the right fix — narrow the types instead.

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
- `'elementEnabled'` — Can be used as an element inside an Experience composition (columns/rows). This is the correct way to define elements.

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

These are NOT auto-registered. If your CMS uses Blank Experience or Blank Section content (the default Visual Builder building blocks), you MUST include them in `initContentTypeRegistry`:

```typescript
initContentTypeRegistry([
  BlankExperienceContentType,  // required if Visual Builder experiences are used
  BlankSectionContentType,     // required if Visual Builder sections are used
  ...yourContentTypes,
]);
```

Do not create new content types called `BlankExperience` or `BlankSection` — those keys already exist.

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
| Component prop | `content` | `function HeroBlock({ content, displaySettings })` |

> Older v1-style code uses `opti` instead of `content` as the prop name. Both work; v2 docs and new repos use `content`. Stay consistent within a project.

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

A display template targets exactly one of:
- `contentType: 'MyType'` — apply to a specific content type
- `baseType: '_component' | '_experience' | '_section'` — apply to all content types of a base type
- `nodeType: 'row' | 'column'` — apply to grid structural nodes (Visual Builder)

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
  content: ContentProps<typeof ButtonElementCT>;
  displaySettings?: ContentProps<typeof ButtonDisplayTemplate>;
};

export default function ButtonElement({ content, displaySettings }: Props) {
  const style = displaySettings?.style ?? 'primary';
  return <Button variant={style}>{content.text}</Button>;
}
```

See `references/standard-types.md` for more display template examples and the two component-variant registration patterns (`tag` + `{ default, tags }` vs `'Key:Tag'` colon syntax).

## React Component Pattern

The SDK exposes the helpers your content-type components consume:

```typescript
import { ContentProps, damAssets } from '@optimizely/cms-sdk';
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';
import { RichText } from '@optimizely/cms-sdk/react/richText';

type Props = {
  content: ContentProps<typeof ArticlePageCT>;
};

export default function ArticlePage({ content }: Props) {
  const { pa, src } = getPreviewUtils(content);
  const { getAlt } = damAssets(content);

  return (
    <article>
      <h1 {...pa('heading')}>{content.heading}</h1>

      {content.featuredImage && (
        <img
          src={src(content.featuredImage)}
          alt={getAlt(content.featuredImage, 'Article hero')}
        />
      )}

      <div {...pa('body')}>
        <RichText content={content.body?.json} />
      </div>
    </article>
  );
}
```

- `pa('propertyName')` — spreads preview attributes that enable click-to-edit in the Visual Builder.
- `src(reference)` — resolves a content-reference URL; in preview mode automatically appends the preview token.
- `damAssets(content)` — `getSrcset`, `getAlt`, `isDamImageAsset`/`isDamVideoAsset`/`isDamRawFileAsset`, `getDamAssetType`, `isDamAsset`. See `references/dam-assets.md`.
- `RichText` — Slate.js renderer with customisable elements/leafs. See `references/rich-text.md`.

Detailed registry wiring (`initContentTypeRegistry`, `initReactComponentRegistry`) and the preview route (`/preview`, `withAppContext`, `PreviewComponent`) belong to the `optimizely-cms-nextjs` skill. A minimal registry note for content-type developers lives in `references/visual-builder-preview.md`.

## GraphClient — Fetching Content (quick reference)

v2 recommends configuring once and reading via `getClient()`:

```typescript
// At app entry (e.g. src/optimizely.ts, imported from layout.tsx)
import { config } from '@optimizely/cms-sdk';

config({
  apiKey: process.env.OPTIMIZELY_GRAPH_SINGLE_KEY,
  graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
});
```

```typescript
// Anywhere a fetch is needed
import { getClient } from '@optimizely/cms-sdk';

const client = getClient();
const content = await client.getContentByPath('/about-us/');
```

`new GraphClient(key, options)` still works for explicit construction. Full method reference (`getContent`, `getContentByPath`, `getPath`, `getItems`, `getPreviewContent`, `request`, GraphReference format) in `references/graph-client.md`.

## Adding a New Content Type (Checklist)

1. Create `src/content-types/NewType.ts` — define with `contentType()`, export as `NewTypeCT`
2. Export from `src/content-types/index.ts`
3. Create component in `src/components/{pages,blocks,elements}/NewType.tsx`
4. Export from `src/components/index.ts`
5. Add to resolver map in `src/optimizely.ts` (`initReactComponentRegistry`)
6. Add file path to `optimizely.config.mjs` components array
7. Run `npx @optimizely/cms-cli@latest config push ./optimizely.config.mjs` to sync to CMS

## Best Practices

1. **Check built-in metadata first** — Use `content._metadata.published`, `.created`, etc. instead of creating redundant date/title properties
2. **Use camelCase for property keys** — Follow SDK conventions
3. **Always add displayName** — Makes the CMS editor user-friendly
4. **Export with "CT" suffix** — e.g., `HeroBlockCT`, `ArticlePageCT`
5. **Distinguish url vs link** — `url` for simple URLs, `link` for rich links with text/title/target
6. **Use displayTemplate for visual styling** — Don't put colors, sizes, or layout variants in content type enum properties
7. **Use `_component` + `compositionBehaviors: ['elementEnabled']` for Visual Builder elements** — Button, Title, Image, etc.
8. **Respect element property restrictions** — On any `_component` with `elementEnabled`, avoid `content`, `component`, `json`, and arrays of content items
9. **Constrain `content`/`contentReference` properties** — Always specify `allowedTypes` or `restrictedTypes` to keep GraphQL fragments small
10. **No nested arrays** — Arrays cannot contain array items
11. **Config uses file paths** — `optimizely.config.mjs` must use `components` with string globs/paths, not imported objects
12. **Use `ContentProps<typeof X>`** — For type-safe component props inferred from content types
13. **Use `damAssets()` for media** — Handles srcset, alt text, preview tokens automatically
14. **Use `RichText` for rich-text content** — Customise via `elements`/`leafs` props; don't dangerouslySetInnerHTML

## CMS CLI & Syncing

See `references/cli-setup.md` for full CLI documentation including installation, `optimizely.config.mjs` setup, glob patterns + negation, new v2 commands and flags.

Quick reference:
```bash
npx @optimizely/cms-cli@latest config push ./optimizely.config.mjs   # Push to CMS
npx @optimizely/cms-cli@latest config pull --output ./src/content-types --group   # Pull from CMS
npx @optimizely/cms-cli@latest content delete <Key>                  # Delete one type
```

## Visual Builder Registry

See `references/visual-builder-preview.md` for the registry init details (`BlankExperienceContentType`, `BlankSectionContentType`). The preview route itself (`/preview`, `withAppContext`, `communicationinjector.js`) is covered by the `optimizely-cms-nextjs` skill.

## References

- `references/property-types.md` — Complete property type reference with all options
- `references/standard-types.md` — Ready-to-use page, block, and element examples + display template patterns
- `references/validation.md` — Validation patterns, regex examples, choice-key naming rules
- `references/composition-patterns.md` — Advanced composition and Visual Builder grid patterns
- `references/troubleshooting.md` — Common errors and solutions
- `references/cli-setup.md` — CMS CLI v2 installation, config, sync, and new commands/flags
- `references/visual-builder-preview.md` — Registry init for Visual Builder (preview route → nextjs skill)
- `references/graph-client.md` — GraphClient v2 API: `config()`, `getClient()`, GraphReference, all methods
- `references/dam-assets.md` — DAM asset helpers (srcset, alt, type guards)
- `references/rich-text.md` — RichText component: elements, leafs, decodeHtmlEntities, custom rendering
- `references/react-integration.md` — React component pattern + registry overview (full wiring → nextjs skill)
- [Official SDK docs](https://github.com/episerver/content-js-sdk/tree/main/docs) — Authoritative source for v2 changes
