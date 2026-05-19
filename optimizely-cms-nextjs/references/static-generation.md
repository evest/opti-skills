# Static Generation + ISR

The canonical pattern in this project is **deliberately not to pre-render real pages at build**. `generateStaticParams` returns a placeholder per locale; real pages fill into the shared Redis cache on first request. This page explains why.

## TL;DR

| Concern | Decision |
|---|---|
| Pre-render every CMS page at `next build` | **No** |
| `generateStaticParams` for `[[...slug]]` | Returns one placeholder slug per locale |
| `generateStaticParams` for the locale layout | Returns `routing.locales` (cheap, no Graph) |
| First request per URL after deploy | Pays Graph latency for TTFB; fills shared cache |
| Subsequent requests across all replicas | Cache HIT via shared Redis handler |
| Cache invalidation on publish | `/hooks/graph` webhook → `revalidatePath(path)` |
| Sitemap freshness | `cacheLife('hours')` + tag invalidation by webhook |

## The placeholder pattern

```ts
// src/lib/optimizely/all-pages.ts
import { routing } from '@/i18n/routing';

export const PLACEHOLDER_SLUG_SEGMENT = '__no-cms-pages-at-build__';

type LocaleSlug = { locale: string; slug?: string[] };

const PLACEHOLDER: LocaleSlug[] = routing.locales.map((locale) => ({
  locale,
  slug: [PLACEHOLDER_SLUG_SEGMENT],
}));

export function getAllPagesPaths(): LocaleSlug[] {
  return PLACEHOLDER;
}
```

```ts
// src/lib/optimizely/get-page.ts (relevant fragment)
export async function getPageContent(slug: string[]) {
  'use cache';
  cacheLife('max');
  cacheTag(getPageTag(slug));

  if (slug.includes(PLACEHOLDER_SLUG_SEGMENT)) {
    return null;          // short-circuit — never hits Graph
  }
  // ... normal fetch path
}
```

`cacheComponents` requires `generateStaticParams` to return at least one entry. The placeholder satisfies that rule cheaply — no Graph call, no chance of build-time failure.

## Why we don't pre-render real pages

Three reasons, all observed in production:

1. **DXP build container has unreliable outbound connectivity to Optimizely Graph.** We've seen `HeadersTimeoutError` and 50s `'use cache'` fill timeouts on individual real pages during Test2 builds.

2. **A timed-out Graph fetch inside `'use cache'` fails the build, and is unrecoverable.** The alternative — recording a null result and 404'ing the page — silently breaks real published pages until the next deploy or webhook event. Either way, build success becomes coupled to Graph availability, which is the opposite of what static generation should buy us.

3. **Pages are perfectly cacheable at runtime via the shared Redis cache handler.** First request per URL pays Graph latency for TTFB; every subsequent request across all replicas is a cache HIT. The webhook invalidates per-page on publish.

Net effect: **build never depends on Graph**. Cache fills happen on first request per URL after deploy. The TTFB penalty for the first hit per URL is acceptable because the shared cache makes it amortise over every subsequent hit, on every replica, until the next publish.

## Locale layout's `generateStaticParams`

The locale layout's `generateStaticParams` is cheap — pure local data:

```tsx
// src/app/[locale]/layout.tsx
import { routing } from '@/i18n/routing';

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}
```

This tells Next.js to pre-render the layout shell for each locale at build. Header, footer, locale-aware translations — all bake in. The placeholder catch-all under it then prevents any per-slug prerender.

## Catch-all uses optional brackets

```
src/app/[locale]/[[...slug]]/page.tsx
              ^^^^^^^^^^^
              double brackets = optional catch-all
```

Optional catch-all (double brackets) matches both `/no/` (no slug → `slug` is `undefined`) and `/no/about/` (slug is `['about']`). Single-bracket `[...slug]` would NOT match the locale root — `/no/` would fall through to the locale layout with no page match.

```ts
// In the page
function fullSlug(locale: string, slug?: string[]): string[] {
  return [locale, ...(slug ?? [])];
}
```

So `getPageContent(['no'])` fetches `/no/` (the locale root) and `getPageContent(['no', 'about'])` fetches `/no/about/`. Both go through the same fetcher, same cache, same tag scheme.

## Behaviour at build time

```
next build
├── Root layout evaluated → src/optimizely.ts side-effect runs config() + 3 registries
├── [locale]/layout generateStaticParams → [{locale:'en'},{locale:'no'},{locale:'sv'},{locale:'da'}]
├── [locale]/[[...slug]] generateStaticParams → [
│     {locale:'en', slug:['__no-cms-pages-at-build__']},
│     {locale:'no', slug:['__no-cms-pages-at-build__']},
│     ...
│   ]
├── For each placeholder pair, render → getPageContent short-circuits → returns null
│   → notFound() commits 404 → 404 response prerendered for the placeholder URL
└── Bundle into .next/
```

The placeholder URLs are never reachable by users (no editor would publish a page at `/no/__no-cms-pages-at-build__/`). They exist solely to satisfy the framework's "≥1 entry" rule.

## Behaviour at runtime

First request to `/no/about/`:
1. No prerendered HTML matches → on-demand render
2. `getPageContent(['no', 'about'])` — cache miss → calls Graph → fills Redis cache entry tagged `opti-page:no/about`
3. HTML rendered, returned

Second request to `/no/about/` (any replica):
1. Cache HIT in Redis → `getPageContent` resolves to cached result without Graph call
2. HTML rendered, returned

Editor publishes `/no/about/`:
1. CMS webhook POSTs `/hooks/graph` with the docId
2. Webhook resolves docId → URL → calls `revalidatePath('/no/about')` and `revalidateTag(getPageTag([...]), 'max')`
3. Redis entries for that page deleted
4. Next request re-fills the cache

Editor publishes `/no/blog/post-1/`:
1. Same flow + ancestor-prefix invalidation of `getArticlesUnderTag('/no/', 'no')` and `getArticlesUnderTag('/no/blog/', 'no')` so any article-listing block on parent pages re-fetches

## Sitemap generation

The sitemap is the one place that walks every CMS page at runtime (not build):

```ts
// src/lib/optimizely/all-content-paths.ts
export async function getAllContentPaths() {
  'use cache';
  cacheLife('hours');
  cacheTag(CACHE_KEYS.PATHS);
  // ... Graph query ...
}

// src/app/sitemap.ts
export default async function sitemap() {
  const paths = await getAllContentPaths();
  return /* ... shape ... */;
}
```

`'hours'` cacheLife is the belt; webhook invalidation of `CACHE_KEYS.PATHS` is the braces. Either keeps the sitemap reasonably fresh.

## When to switch to real prerender

Pre-rendering real pages becomes attractive when:
- Graph connectivity from the build container is reliable (true on Vercel, often not on DXP)
- You want SEO crawlers to see the prerendered HTML faster than the first-request fill
- The cache cold-start penalty across all routes matters to your TTI metrics

If you switch, accept the trade-off:
- Build fails when Graph is unreachable
- A build-time `'use cache'` rejection is essentially unrecoverable without a deploy retry

Implementation sketch (DO NOT apply without reading the trade-off above):

```ts
// Replace src/lib/optimizely/all-pages.ts with:
export async function getAllPagesPaths(): Promise<LocaleSlug[]> {
  try {
    const client = getClient();
    // Walk all _Content with usable URLs; group by locale; return slug arrays
    // matching the [[...slug]] route's expected shape.
    // ... see git history / uryga-nextjs for a reference implementation ...
  } catch (e) {
    console.error('[all-pages] graph query failed:', e);
    return /* still return placeholder per-locale so build doesn't break */;
  }
}
```

The fallback to placeholder on error preserves "build never fails" while attempting real prerender on the happy path. This is the conservative migration.

## ISR revalidation on publish

When `/hooks/graph` fires for a CMS publish:
- **Page URL** → `revalidatePath(path)` → exact-route cache entry blown
- **Page parents** → `revalidateTag(getArticlesUnderTag(parent, locale), 'max')` for each ancestor → any listing block re-fetches
- **Sitemap** → `revalidateTag(CACHE_KEYS.PATHS, 'hours')` → sitemap re-fills next request

`revalidatePath` and `revalidateTag` mark cache entries stale but don't prefetch. The next in-flight request triggers the re-render.

## Debugging "my page renders but isn't prerendered"

In this project, **no page is prerendered by design** — every page is runtime-cached. If you expected prerender and didn't get it, the placeholder pattern is the cause.

If you actually need prerender for one specific page (e.g. a marketing landing page that's heavily promoted), the cleanest path is:

1. Don't replace `getAllPagesPaths` wholesale.
2. Add a dedicated route file with its own `generateStaticParams` returning that one slug.
3. Or accept the runtime cache fill — the first request after deploy is typically < 1s and every subsequent request is < 50ms.

## Debugging "the cache isn't sharing across replicas"

If `revalidateTag` works locally but not in DXP:
1. Check `cache-handler.mjs` is referenced in `next.config.ts`'s `cacheHandler`.
2. Check `cacheMaxMemorySize: 0` — without this, Next.js keeps an in-process LRU per replica that the handler can't invalidate.
3. Check DXP logs for `[cache] Redis cluster connected` — if you see `Redis unavailable, falling back to in-memory`, replicas are running their own caches and `revalidateTag` only invalidates the one that received the webhook.
4. Check `REDIS_URL`, `AZURE_CLIENT_ID`, `OPTIMIZELY_DXP_DEPLOYMENT_ID` are present in DXP env.
