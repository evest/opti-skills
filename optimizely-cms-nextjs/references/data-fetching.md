# Data Fetching + Caching

Every page/component that reads from the CMS uses `GraphClient` + `'use cache'`. This ref covers the full shape of that pattern and the non-obvious rules.

## The base pattern

```ts
import { GraphClient } from '@optimizely/cms-sdk'
import { cacheLife, cacheTag } from 'next/cache'

async function getSomething(locale: string) {
  'use cache'                                     // line 1 of body — MUST be literal directive
  cacheLife('max')                                // long-lived; revalidate via tag/path, not TTL
  cacheTag(getCacheTag(CACHE_KEYS.HEADER, locale)) // optional; attach revalidation tag

  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })
  return client.getContentByPath(`/${locale}/some/path/`)
}
```

## The `'use cache'` rules

1. **First statement of the function body.** Not after other code, not after a `try`, not inside an arrow function's parens. Comments are allowed above but nothing executable.
2. **Requires `cacheComponents: true`** in `next.config.ts`. Without it, throws at runtime.
3. **Only valid on async functions that return serializable values.** Return `null`/plain object/array of plain objects. Class instances, Dates, Maps can cause hydration mismatches.
4. **Inputs are part of the cache key.** Different `locale` → different cache entry. Pass only primitives as arguments — no request objects, no fn references.
5. **Closed-over variables are captured by reference**, not value. A module-level `let` that changes between requests will NOT re-key the cache. Always take all dynamic inputs as function parameters.

## `cacheLife` values

```ts
cacheLife('max')       // effectively permanent — invalidate via revalidateTag/revalidatePath
cacheLife('default')   // Next.js default (short; read node_modules/next/dist/docs/)
cacheLife({ revalidate: 3600, expire: 86400 })  // custom, numeric seconds
```

For CMS-backed content the canonical choice is `'max'` (≈ 30-day revalidate / 1-year expire window). Rationale: **CMS content changes are publish-events, not time-based events**. An author pressing Publish is a discrete signal; waiting N minutes for a poll to pick it up is strictly worse. The webhook drives freshness; `cacheLife('max')` tells Next.js not to second-guess that.

Use shorter `cacheLife` values only for data that genuinely drifts on a timer (stock levels, live scores, etc.) — not for CMS output.

## `cacheTag` — when to use it

Attach a tag when the *same* cached value needs to be invalidated by something other than a URL path change.

Use cases:
- **Header/Footer** — shared across every page; invalidate once per locale on publish.
- **Cross-cutting content** — e.g. a "featured products" list that lives on many pages.
- **Content-type-scoped invalidation** — "rebuild every page that uses the Promotions content type".

Not needed for:
- **Regular pages** — the webhook calls `revalidatePath(urlWithLocale)` directly, which already targets the path-based cache.

## The cache-keys helper

```ts
// lib/cache/cache-keys.ts
export const CACHE_KEYS = {
  FOOTER: 'optimizely-footer',
  HEADER: 'optimizely-header',
} as const

export function getCacheTag(
  baseKey: (typeof CACHE_KEYS)[keyof typeof CACHE_KEYS],
  locale: string,
): string {
  return `${baseKey}-${locale}`
}
```

Produces tags like `optimizely-header-en`. Never hardcode tag strings elsewhere — one call site per tag, always via `getCacheTag`.

## Revalidation pairing

When you write `cacheTag('X')`, you MUST invalidate with `revalidateTag('X', 'max')` — the second argument's `'max'` matches the `cacheLife('max')` used on the cached function. Omitting the second arg silently fails to invalidate long-lived entries.

Path revalidation does not need a second arg: `revalidatePath('/en/about')`.

## Error handling — the two valid patterns

The rule is "**never let a `'use cache'` function throw**" — during static prerender, an uncaught throw surfaces as `HANGING_PROMISE_REJECTION` that component-level try/catch cannot intercept.

But there are two practical reads on this:

### Pattern A — Try/catch inside `'use cache'` (safest)
Used for **shared content** (header/footer) where failure = "render without it":

```ts
async function getHeaderContent(locale: string) {
  'use cache'
  cacheLife('max')
  cacheTag(getCacheTag(CACHE_KEYS.HEADER, locale))

  try {
    const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
      graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
    })
    const content = await client.getContentByPath(`/${locale}/header/`)
    return content[0] ?? null
  } catch {
    return null        // never throws — prerender-safe
  }
}
```

### Pattern B — Try/catch at caller + `notFound()` (used for pages)
Used for **page data** where failure = "404":

```ts
async function getHomepageContent(locale: string) {
  'use cache'
  cacheLife('max')
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })
  return client.getContentByPath(`/${locale}/`)   // returns [] on 404, doesn't throw
}

export default async function Page({ params }: Props) {
  const { locale } = await params
  try {
    const [c] = await getHomepageContent(locale)
    return <OptimizelyComponent content={c} />
  } catch {
    return notFound()
  }
}
```

This pattern relies on `GraphClient.getContentByPath` returning an empty array (not throwing) when the path doesn't resolve. Genuine runtime errors (auth, network) do throw and the component-level catch handles them *at request time* — by which point we're past prerender.

**When in doubt, prefer Pattern A.** It's robust to any error source. Pattern B works because the example relies on GraphClient's "empty array on miss" behaviour.

## `GraphClient` — instantiation

```ts
const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
  graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  // host?:                   string    — multi-site filter
  // maxFragmentThreshold?:   number    — default 100, raise for very deep schemas
  // cache?:                  boolean   — default true
  // slot?:                   'Current' | 'New'  — during Graph index rebuild
})
```

Don't cache the client across requests if you mutate options; it's cheap to construct per-request. The `'use cache'` wrapping captures the resolved fetch result, not the client.

## `GraphClient` — methods used in the Next.js patterns

| Method | When |
|---|---|
| `client.getContentByPath(path, options?)` | Page data — returns `T[]` (possibly empty, typically 1 item) |
| `client.getContent(reference, options?)` | Single-item by `{ key, locale?, version? }` — returns item or null |
| `client.getPath(input, options?)` | Breadcrumb / ancestor chain — returns `PathItem[]` top-to-current |
| `client.getItems(input, options?)` | Child pages — returns `PathItem[]` |
| `client.getPreviewContent(params, options?)` | Draft content in `/preview` route — takes `PreviewParams` from searchParams |
| `client.request(query, variables, previewToken?, cache?, slot?)` | Raw GraphQL — used by `getAllPagesPaths` and the webhook |

Full signatures and option shapes live in `D:\Dev\content-js-sdk\docs\5-fetching.md` and in the content-types skill's `references/graph-client.md`. This skill focuses on how these methods compose with `'use cache'`.

### How `getContentByPath` actually works under the hood

Internally the SDK does a **two-step** query:

1. Fetch `_metadata` for the path — learn what `__typename` lives there.
2. Build a typed content query from the resolved type name and fetch again with full field selection.

Implications:
- You never hand-write GraphQL fragments for normal page fetches — the SDK composes them from your registered content types.
- This is why schema sync matters: if the CMS has `HeroBlock` but code doesn't, step 2 selects fields that don't exist and returns incomplete data. If code has `HeroBlock` but CMS doesn't, step 1 returns no type and the fetch returns `[]`.
- SDK source: `https://github.com/episerver/content-js-sdk/blob/main/packages/optimizely-cms-sdk/src/graph/index.ts#L357`

## Variation filtering

```ts
const content = await client.getContentByPath('/en/landing/', {
  variation: { include: 'SOME', value: ['variant-a'] },
})
```

`include` values: `'ALL'` | `'SOME'` | `'NONE'`. Remember: the variation selection becomes part of the URL-keyed result, but NOT automatically part of the cache key. If you fetch different variants, pass the variation id as an explicit parameter to your `'use cache'` wrapper so the cache keys differ.

## Raw GraphQL (when you need it)

The webhook and `getAllPagesPaths` use `client.request(...)` directly because they need specific field selections. Pattern:

```ts
const response = await client.request(
  `query GetWhatever($foo: String) { ... }`,
  { foo: 'bar' } as any,         // SDK variable typing is incomplete — cast is known-acceptable
)
```

The `as any` cast is a known SDK limitation. Use it consistently; don't invent elaborate type plumbing around it.

## Anti-patterns

- **`'use cache'` with a non-deterministic input**: `Date.now()`, `Math.random()`, `cookies()`, `headers()`. These either don't cache usefully or throw.
- **Calling `revalidateTag(tag)` without `'max'`** when the cached function used `cacheLife('max')`. Silently no-op.
- **Forgetting `cacheComponents: true`** in `next.config.ts`. Runtime error, not a build error.
- **Manually forwarding the preview token** to `GraphClient` — `getPreviewContent` and the `src()` helper from `getPreviewUtils` already handle this.
- **Reading secrets inside `'use cache'`** — the result is cached and returned to every caller; reading `OPTIMIZELY_GRAPH_SINGLE_KEY` inside the function is fine (it's not returned), but never return a secret from a cached function.
- **Throwing a typed error class to trigger `notFound()` from inside `'use cache'`** — the throw doesn't unwind the way you expect during prerender. Return null and have the caller decide.
