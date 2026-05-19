# GraphClient API Reference (v2)

`GraphClient` fetches content from Optimizely Graph. v2 adds a recommended `config()` + `getClient()` pattern; direct construction with `new GraphClient()` still works.

> This is a quick reference focused on what content-type developers need. Detailed wiring (where to call `config()` in a Next.js app, caching strategy, `withAppContext`, preview routes, ISR) belongs to the `optimizely-cms-nextjs` skill.

## Recommended: `config()` + `getClient()`

Configure once at the application entry point:

```typescript
// src/optimizely.ts (imported from root layout)
import { config } from '@optimizely/cms-sdk';

config({
  apiKey: process.env.OPTIMIZELY_GRAPH_SINGLE_KEY,
  graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
});
```

Read the configured client anywhere:

```typescript
import { getClient } from '@optimizely/cms-sdk';

const client = getClient();
const content = await client.getContentByPath('/about-us/');
```

### `config()` options

| Option | Required | Description |
|--------|----------|-------------|
| `apiKey` | yes | Optimizely Graph Single Key (CMS → Settings → API Keys → Render Content) |
| `graphUrl` | no | Graph endpoint. Default `https://cg.optimizely.com/content/v2`. Use staging URL for cmstest |
| `host` | no | Default application host for path filtering (multi-site setups). Per-request override available |
| `maxFragmentThreshold` | no | Fragment-count warning threshold (default `100`). See "Fragment performance" below |
| `cache` | no | Enable/disable server-side caching for all queries. Default `true` |
| `slot` | no | Select Graph index: `'Current'` or `'New'` (used during smooth rebuilds) |

### Why prefer `getClient()` over `new GraphClient()`

- **Single config point** — change API key/Graph URL in one place
- **No env-var threading** — pages/components don't need to import `process.env`
- **Easier to test/mock** — one configuration surface

## Legacy: direct construction

Still fully supported:

```typescript
import { GraphClient } from '@optimizely/cms-sdk';

const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
  graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
  host: 'https://example.com',          // optional
  maxFragmentThreshold: 150,            // optional
});
```

**Environment variables:**
```bash
OPTIMIZELY_GRAPH_SINGLE_KEY=your-single-key             # From CMS > Settings > API Keys > Render Content
OPTIMIZELY_GRAPH_GATEWAY=https://cg.optimizely.com/content/v2   # Production (default)
# Or staging: https://cg.staging.optimizely.com/content/v2
```

## Methods

### `getContentByPath(path, options?)`

Fetch content by URL path. Returns an array of matching items.

```typescript
const content = await client.getContentByPath('/about-us/');

// With variation filtering
const content = await client.getContentByPath('/products/', {
  variation: { include: 'SOME', value: ['variation-id'] },
});

// With host filtering (multi-site)
const content = await client.getContentByPath('/home/', {
  host: 'www.example.com',
});
```

**Parameters:**
- `path: string` — Content URL path (e.g. `'/about-us/'`)
- `options?`
  - `variation?` — Filter by variation, e.g. `{ include: 'SOME', value: ['…'] }`
  - `host?: string` — Override host for this request

**Returns:** `Promise<any[]>` — array of items (empty if none found)

> Trailing slash matters: use `/en/` not `/en`. Include the locale segment.

### `getContent(reference, previewToken?)` *(new in v2)*

Unified fetch via a `GraphReference`. Supports key + locale + version, or a `graph://` string.

```typescript
// Latest published by key
const content = await client.getContent({ key: '880777d5a2824399b07e93e3ca70668e' });

// Specific locale
const content = await client.getContent({
  key: '880777d5a2824399b07e93e3ca70668e',
  locale: 'en',
});

// Specific version (takes priority over locale)
const content = await client.getContent({
  key: '880777d5a2824399b07e93e3ca70668e',
  version: '123',
});

// graph:// string format
const content = await client.getContent(
  'graph://cms/Page/880777d5a2824399b07e93e3ca70668e?loc=en&ver=123'
);

// With a preview token (for draft content)
const content = await client.getContent(
  { key: '880777d5a2824399b07e93e3ca70668e', version: '123' },
  'preview-token'
);
```

**GraphReference fields:**
- `key` (required) — Content GUID/key
- `locale?` — Content locale (`'en'`, `'sv'`, etc.)
- `version?` — Specific version (takes priority over locale)
- `type?` — Content type name
- `source?` — Source identifier (reserved for future use)

**String format:** `graph://[source]/[type]/<key>?loc=<locale>&ver=<version>`

**Priority:** `version` > `locale` > latest published.

> `getContent()` always returns published content. To fetch drafts, use `getPreviewContent()` with a preview token.

### `getPath(input, options?)`

Get ancestor pages (breadcrumb) for a given path.

```typescript
// By URL path
const ancestors = await client.getPath('/blog/my-article/');

// By GraphReference (v2)
const ancestors = await client.getPath({
  key: '880777d5a2824399b07e93e3ca70668e',
  locale: 'en',
});

// With locale filter
const ancestors = await client.getPath(
  { key: '880777d5a2824399b07e93e3ca70668e' },
  { locales: ['en', 'sv'] }
);
```

**Parameters:**
- `input: string | GraphReference` — URL path or content reference
- `options?`
  - `host?: string` — Override host (URL-path form only)
  - `locales?: string[]` — Filter by locales

**Returns:** Array of page metadata sorted root → current, or `null` if not found.

### `getItems(input, options?)`

Get direct children of a page.

```typescript
const children = await client.getItems('/blog/');

// By GraphReference
const children = await client.getItems({
  key: '880777d5a2824399b07e93e3ca70668e',
  locale: 'en',
});
```

Same `options` shape as `getPath`. Returns child page metadata or `null` if parent not found.

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
  ctx: string;       // 'default' | 'edit' | 'preview'
  ver: string;
  loc: string;
}
```

When called inside a route wrapped with `withAppContext` from `@optimizely/cms-sdk/react/server`, `getPreviewContent` automatically populates the request-scoped context with the preview parameters. Components below can then read them via `getContextData('preview_token' | 'locale' | 'key' | 'version' | 'mode')`. Detailed preview-route wiring lives in the `optimizely-cms-nextjs` skill.

### `request(query, variables, previewToken?)`

Execute a raw GraphQL query.

```typescript
const result = await client.request(
  `query { ArticlePage { items { heading body { html } } } }`,
  {},
  previewToken  // optional
);
```

## Content Type Registration

The GraphClient requires content types to be registered for proper type resolution:

```typescript
import {
  initContentTypeRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';

initContentTypeRegistry([
  BlankExperienceContentType,  // if Visual Builder experiences are used
  BlankSectionContentType,     // if Visual Builder sections are used
  ArticlePageCT,
  HeroBlockCT,
  // ... all your content types
]);
```

`initContentTypeRegistry` **replaces** the registry — built-in types are not merged automatically. Register them explicitly when needed.

The repository's `src/optimizely.ts` (imported from `app/layout.tsx`) is the conventional place for this in a Next.js project. Full wiring in the `optimizely-cms-nextjs` skill.

## Fragment performance (v2 warning)

The SDK emits a console warning when generating a fragment that exceeds `maxFragmentThreshold` inner fragments:

```
⚠️ [optimizely-cms-sdk] Fragment "MyContentType" generated 200 inner fragments (limit: 100).
→ Consider narrowing it using allowedTypes and restrictedTypes or reviewing schema references to reduce complexity.
```

This usually means a `content` or `contentReference` property has no `allowedTypes`/`restrictedTypes`, so the SDK emits fragments for every possible content type the property could resolve to.

**Fix:**
1. Add `allowedTypes` or `restrictedTypes` to constrain what the property accepts (preferred).
2. Or, as a last resort, raise the threshold: `config({ maxFragmentThreshold: 200 })`.

## Example: Next.js catch-all route

```typescript
// src/app/[locale]/[[...slug]]/page.tsx
import { getClient, ContentProps } from '@optimizely/cms-sdk';
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';

type Props = {
  params: Promise<{ locale: string; slug?: string[] }>;
};

export default async function Page({ params }: Props) {
  const { locale, slug = [] } = await params;
  const client = getClient();

  const content = await client.getContentByPath(`/${locale}/${slug.join('/')}/`);

  if (!content?.[0]) return <div>Not found</div>;

  return <OptimizelyComponent content={content[0]} />;
}
```

For the full Next.js pattern (cacheLife, cacheTag, generateStaticParams, locale middleware, revalidation webhook), see the `optimizely-cms-nextjs` skill.
