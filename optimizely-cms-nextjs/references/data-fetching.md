# Data Fetching + Caching

Every page/component that reads from the CMS uses `getClient()` + `'use cache'`. This ref covers the full shape of that pattern and the non-obvious rules.

## The base pattern

```ts
import { getClient } from '@optimizely/cms-sdk';
import { cacheLife, cacheTag } from 'next/cache';
import { getPageTag } from '@/lib/cache/cache-keys';

async function getSomething(slug: string[]) {
  'use cache';                          // line 1 of body — MUST be literal directive
  cacheLife('max');                     // long-lived; revalidate via tag/path, not TTL
  cacheTag(getPageTag(slug));           // optional; attach revalidation tag

  try {
    const client = getClient();
    const items = await client.getContentByPath(`/${slug.join('/')}/`);
    return items?.[0] ?? null;
  } catch (e) {
    console.error('[fetcher] graph lookup failed:', e);
    return null;                        // never throw under 'use cache' — see "Error handling"
  }
}
```

## The `'use cache'` rules

1. **First statement of the function body.** Not after other code, not after a `try`, not inside an arrow function's parens. Comments above are allowed.
2. **Requires `cacheComponents: true`** in `next.config.ts`. Without it, throws at runtime.
3. **Only valid on async functions that return serializable values.** Return `null` / plain object / array of plain objects. Class instances, Dates, Maps can cause hydration mismatches.
4. **Inputs are part of the cache key.** Different arguments → different cache entry. Pass only primitives — no request objects, no function references.
5. **Closed-over variables are captured by reference**, not value. A module-level `let` that changes between requests will NOT re-key the cache. Always take dynamic inputs as function parameters.

## `cacheLife` profiles

```ts
cacheLife('max')         // effectively permanent — invalidate via revalidateTag / revalidatePath
cacheLife('hours')       // ~1 hour stale-while-revalidate, ~24h expiry
cacheLife('default')     // Next.js default — short; rarely the right choice for CMS data
cacheLife({ revalidate: 3600, expire: 86400 })  // custom numeric seconds
```

For CMS-backed content, `'max'` is the right default. CMS content changes are **publish events**, not time-based. An author pressing Publish is a discrete signal; waiting N minutes for a poll to pick it up is strictly worse than letting the webhook drive freshness.

Use shorter `cacheLife` only for data that genuinely drifts on a timer:
- **Sitemap** uses `cacheLife('hours')` because the webhook revalidates the `PATHS` tag anyway — the time fallback is belt-and-braces for the case where a publish slipped past the webhook.
- **Stock levels, live scores, etc.** would warrant short profiles — but that's not CMS-backed content.

## `cacheTag` — when to use it

Attach a tag when the cached value needs to be invalidated by something other than a URL path change. The webhook composes the same tag and calls `revalidateTag(tag, 'max')`.

Patterns in `nextjs-fe-hosting`:

```ts
// src/lib/cache/cache-keys.ts
export const CACHE_KEYS = {
  PAGE: 'opti-page',
  PATHS: 'opti-paths',
  ARTICLES_UNDER: 'opti-articles-under',
} as const;

export function getPageTag(slug: string[]): string {
  const suffix = slug.length === 0 ? 'root' : slug.join('/');
  return `${CACHE_KEYS.PAGE}:${suffix}`;
}

export function getArticlesUnderTag(parentPath: string, locale: string): string {
  const parent = parentPath.endsWith('/') ? parentPath : `${parentPath}/`;
  return `${CACHE_KEYS.ARTICLES_UNDER}:${parent}:${locale}`;
}
```

Tags use `:` as separator so the suffix can contain `/` without encoding tricks. One callsite per logical key prevents typos that would silently desync the cache from its invalidator.

Use cases:
- **Per-page tag** — `getPageTag(slug)` on every page fetcher. Webhook composes the same tag to invalidate exactly that page on publish.
- **Listing tag with ancestor prefix** — `getArticlesUnderTag(parent, locale)` on the article-list block; webhook invalidates every ancestor prefix on every article publish.
- **Cross-cutting** — `CACHE_KEYS.PATHS` on the sitemap; any publish invalidates it.

Not needed for one-off page fetches where `revalidatePath` is sufficient — but the project's convention is to tag every CMS fetcher for consistency.

## Revalidation pairing — the `'max'` second arg

When you write `cacheLife('max')`, you MUST invalidate with `revalidateTag(tag, 'max')`. The second argument matches the cacheLife profile. Omitting it silently fails to invalidate long-lived entries.

```ts
// In the fetcher
'use cache';
cacheLife('max');
cacheTag(getPageTag(slug));

// In the webhook
revalidateTag(getPageTag(slugFromUrl), 'max');   // ✅ correct
revalidateTag(getPageTag(slugFromUrl));          // ❌ silent no-op
```

For `cacheLife('hours')` → `revalidateTag(tag, 'hours')`. For paths:

```ts
revalidatePath('/no/about');   // no second arg needed
```

## Error handling — never let `'use cache'` throw

The rule is "**never let a `'use cache'` function throw**". During static prerender (or first-request cache fill), an uncaught throw surfaces as `HANGING_PROMISE_REJECTION` that the component-level try/catch cannot intercept.

### Pattern: try/catch inside the cached function, return null on failure

```ts
export async function getPageContent(slug: string[]) {
  'use cache';
  cacheLife('max');
  cacheTag(getPageTag(slug));

  try {
    const client = getClient();
    const items = await client.getContentByPath(`/${slug.join('/')}/`);
    return items?.[0] ?? null;
  } catch (e) {
    console.error('[get-page] graph lookup failed:', e);
    return null;
  }
}
```

The caller then decides:

```ts
const content = await getPageContent(fullSlug(locale, slug));
if (!content) notFound();   // outside <Suspense> — see "notFound rules"
```

### `notFound` rules under cacheComponents

`notFound()` must be called **outside `<Suspense>`** and **in `generateMetadata`**. The response status commits when the static shell flushes; a `notFound()` thrown from inside a suspended child swaps the body but leaves the 200 OK status — and the CDN happily caches that 200 with a 30-day TTL.

```tsx
// ❌ notFound inside Suspense → 200 OK with notfound body, CDN caches for 30d
async function Page({ params }: Props) {
  return (
    <Suspense>
      <PageContent params={params} />   // PageContent calls notFound() — WRONG
    </Suspense>
  );
}

// ✅ notFound outside Suspense
async function Page({ params }: Props) {
  const { locale, slug } = await params;
  const content = await getPageContent(fullSlug(locale, slug));
  if (!content) notFound();              // commits 404 before shell flush

  return <Suspense><PageContent content={content} /></Suspense>;
}
```

And in `generateMetadata`:
```tsx
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale, slug } = await params;
  const content = await getPageContent(fullSlug(locale, slug));
  if (!content) notFound();    // belt-and-braces; metadata branch also commits the status
  return getSeoMetadata(content as Record<string, unknown>);
}
```

The duplicated `getPageContent` call is cache-free — same arguments → same cache key as the Page call → one Graph hit total.

## `getClient()` — instantiation

Configured once in `src/optimizely.ts`:

```ts
config({
  apiKey: process.env.OPTIMIZELY_GRAPH_SINGLE_KEY,
  graphUrl: getGraphGatewayUrl(),
});
```

Read anywhere:

```ts
const client = getClient();
```

Options exposed on `config()`:
- `apiKey` (required) — Graph Single Key
- `graphUrl` — default `https://cg.optimizely.com/content/v2`
- `host` — multi-site default; per-request override available
- `maxFragmentThreshold` — warning threshold (default 100)
- `cache` — server-side caching for all queries, default true
- `slot` — `'Current'` | `'New'` — used during Graph index rebuilds

`new GraphClient(key, options)` still works for explicit construction. The webhook in `src/app/hooks/graph/route.ts` uses raw `fetch` because it runs at module load (no `getClient()` call yet has set up the cache hooks); for app code, prefer `getClient()`.

## `GraphClient` methods

| Method | When |
|---|---|
| `client.getContentByPath(path, options?)` | Page data — returns `T[]` (possibly empty, typically 1 item) |
| `client.getContent(reference, previewToken?)` | Single-item by `{ key, locale?, version? }` or `graph://` string — returns item or null. **New in v2.** |
| `client.getPath(input, options?)` | Breadcrumb / ancestor chain — accepts URL path or GraphReference |
| `client.getItems(input, options?)` | Child pages — accepts URL path or GraphReference |
| `client.getPreviewContent(params, options?)` | Draft content in `/preview` route — takes `PreviewParams` from searchParams |
| `client.request(query, variables, previewToken?, cache?, slot?)` | Raw GraphQL — used for the sitemap and article-listing queries |

Full signatures, parameter shapes, and the GraphReference format live in the `optimizely-cms-content-types` skill's `references/graph-client.md`. This page focuses on how these methods compose with `'use cache'`.

### How `getContentByPath` works under the hood

Internally the SDK does a **two-step** query:
1. Fetch `_metadata` for the path — learn what `__typename` lives there.
2. Build a typed content query from the resolved type name and fetch again with full field selection.

Implications:
- You never hand-write GraphQL fragments for normal page fetches — the SDK composes them from your registered content types.
- This is why schema sync matters: if the CMS has `HeroBlock` but code doesn't, step 2 selects fields that don't exist and returns incomplete data. If code has `HeroBlock` but CMS doesn't, step 1 returns no type and the fetch returns `[]`.

## Variation filtering

```ts
const items = await client.getContentByPath('/no/landing/', {
  variation: { include: 'SOME', value: ['variant-a'] },
});
```

`include` values: `'ALL'` | `'SOME'` | `'NONE'`. The variation selection becomes part of the URL-keyed result, but NOT automatically part of your `'use cache'` key. If you fetch different variants, pass the variation id as an explicit parameter to your cached wrapper:

```ts
async function getPageContent(slug: string[], variantId?: string) {
  'use cache';
  // variantId now keys the cache
}
```

## Raw GraphQL (when needed)

The sitemap and article-listing queries use `client.request(...)` because they want specific field selections rather than the SDK's auto-composed type fragment.

```ts
// src/lib/optimizely/all-content-paths.ts (abbreviated)
const QUERY = `
  query AllContentPaths($locales: [Locales]) {
    _Content(locale: $locales, limit: 1000) {
      items {
        _metadata { url { default } locale published }
      }
    }
  }
`;

export async function getAllContentPaths() {
  'use cache';
  cacheLife('hours');
  cacheTag(CACHE_KEYS.PATHS);

  try {
    const client = getClient();
    const data = await client.request(QUERY, { locales: routing.locales });
    return /* ... shape into ContentPath[] ... */;
  } catch (e) {
    console.error('[all-content-paths] graph query failed:', e);
    return [];
  }
}
```

The `as any` cast on `client.request(...)` variables (sometimes needed for SDK type incompleteness) is a known SDK limitation. Use it consistently; don't invent elaborate type plumbing around it.

## Article-listing pattern

The listing block uses a parent-path-keyed tag so the webhook can invalidate it whenever any descendant article publishes:

```ts
// src/lib/optimizely/get-articles-under.ts (abbreviated)
export async function getArticlesUnder(parentPath: string, locale: string) {
  'use cache';
  cacheLife('max');
  const parent = parentPath.endsWith('/') ? parentPath : `${parentPath}/`;
  cacheTag(getArticlesUnderTag(parent, locale));

  try {
    const client = getClient();
    const data = await client.request(QUERY, { parent, locale: [locale] });
    return (data?.ArticlePage?.items ?? []).filter(
      (item) =>
        item._metadata?.url?.default !== parent &&
        item._metadata?.url?.default !== parentPath,
    );
  } catch (e) {
    console.error('[get-articles-under] graph query failed:', e);
    return [];
  }
}
```

The webhook invalidates every ancestor prefix on publish (see `references/revalidation-webhook.md`):

```ts
// In the webhook
const segments = path.split('/').filter(Boolean);
for (let i = 1; i < segments.length; i++) {
  const parent = `/${segments.slice(0, i).join('/')}/`;
  revalidateTag(getArticlesUnderTag(parent, locale), 'max');
}
```

For `/no/blog/my-post`, parents `/no/` and `/no/blog/` get tag invalidations. `revalidateTag` on an unwritten tag is a no-op, so over-invalidating costs nothing while keeping listings fresh.

## Anti-patterns

- **`'use cache'` with non-deterministic inputs**: `Date.now()`, `Math.random()`, `cookies()`, `headers()`. These either don't cache usefully or throw.
- **Calling `revalidateTag(tag)` without `'max'`** when the cached function used `cacheLife('max')`. Silent no-op.
- **Forgetting `cacheComponents: true`** in `next.config.ts`. Runtime error, not a build error.
- **Manually forwarding the preview token** to `GraphClient` — `getPreviewContent` and the `src()` helper from `getPreviewUtils` already handle this. `withAppContext` makes the token available via context.
- **Reading secrets inside `'use cache'`** — the result is cached. Reading `process.env.OPTIMIZELY_GRAPH_SINGLE_KEY` inside the function is fine (you don't return it), but never return a secret from a cached function.
- **Throwing a typed error to trigger `notFound()` from inside `'use cache'`** — the throw doesn't unwind the way you expect during prerender. Return null and have the caller decide.
- **Caching at the `getClient()` layer** — don't construct your own LRU around `getClient()`. The SDK's internal cache plus the Next.js Redis handler already cover both layers.
