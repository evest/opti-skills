# GraphClient API Reference

The `GraphClient` class fetches content from Optimizely Graph. Import from `@optimizely/cms-sdk`.

## Setup

```typescript
import { GraphClient } from '@optimizely/cms-sdk';

const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
  graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,  // Optional, defaults to production
});
```

**Environment variables:**
```bash
OPTIMIZELY_GRAPH_SINGLE_KEY=your-single-key      # From CMS > Settings > API Keys > Render Content
OPTIMIZELY_GRAPH_GATEWAY=https://cg.optimizely.com/content/v2  # Production (default)
# Or staging: https://cg.staging.optimizely.com/content/v2
```

## Methods

### `getContentByPath(path, options?)`

Fetch content by URL path. Returns an array of matching items.

```typescript
const content = await client.getContentByPath('/about-us/');

// With variation filtering
const content = await client.getContentByPath('/products/', {
  variation: { name: 'experiment1', value: 'variant-a' },
});

// With host filtering
const content = await client.getContentByPath('/home/', {
  host: 'www.example.com',
});
```

**Parameters:**
- `path: string` — Content URL path (e.g. `'/about-us/'`)
- `options?: GraphGetContentOptions`
  - `variation?: GraphVariationInput` — Filter by variation `{ name, value }`
  - `host?: string` — Filter by hostname

**Returns:** `Promise<any[]>` — Array of content items (empty if none found)

### `getPath(path, options?)`

Get ancestor pages (breadcrumb) for a given path.

```typescript
const ancestors = await client.getPath('/blog/my-article/');
// Returns array sorted from root to current page
// Each item has: _metadata { key, displayName, locale, types, url, sortOrder }
```

**Parameters:**
- `path: string` — Content URL path
- `options?: GraphGetLinksOptions`
  - `host?: string` — Filter by hostname
  - `locales?: string[]` — Filter by locales

### `getItems(path, options?)`

Get child/descendant pages for a given path.

```typescript
const children = await client.getItems('/blog/');
// Returns array of child pages
// Each item has: _metadata { key, displayName, locale, types, url, sortOrder }
```

### `getPreviewContent(params)`

Fetch content for Visual Builder preview mode.

```typescript
import { type PreviewParams } from '@optimizely/cms-sdk';

const preview = await client.getPreviewContent(params as PreviewParams);
```

**PreviewParams shape:**
```typescript
{
  preview_token: string;
  key: string;
  ctx: string;
  ver: string;
  loc: string;
}
```

### `request(query, variables, previewToken?)`

Execute a raw GraphQL query.

```typescript
const result = await client.request(
  `query { ArticlePage { items { heading body { html } } } }`,
  {},
  previewToken  // Optional
);
```

## Content Type Registration

The GraphClient requires content types to be registered for proper type resolution:

```typescript
import { initContentTypeRegistry } from '@optimizely/cms-sdk';

initContentTypeRegistry([
  BlankExperienceContentType,
  BlankSectionContentType,
  ArticlePageCT,
  HeroBlockCT,
  // ... all your content types
]);
```

Register types in your root layout (`src/app/layout.tsx`) before using the GraphClient.

## Example: Next.js Catch-All Route

```typescript
// src/app/[...slug]/page.tsx
import { GraphClient, ContentProps } from '@optimizely/cms-sdk';
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';

type Props = {
  params: Promise<{ slug: string[] }>;
};

export default async function Page({ params }: Props) {
  const { slug } = await params;
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
  });

  const content = await client.getContentByPath(`/${slug.join('/')}/`);

  if (!content?.[0]) return <div>Not found</div>;

  return <OptimizelyComponent content={content[0]} />;
}
```
