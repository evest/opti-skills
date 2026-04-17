# Static Generation + ISR

How the catch-all route pre-renders every CMS page at build time, and how the build gracefully degrades to on-demand ISR when the CMS is unreachable.

## Pieces

- `generateStaticParams()` in `app/[locale]/[...slug]/page.tsx` — returns the list of `{ slug }` objects to pre-render.
- `getAllPagesPaths()` in `lib/optimizely/all-pages.ts` — queries Graph for every `CMSPage` and `SEOExperience` path.
- `mapPathWithoutLocale()` in `lib/optimizely/language.ts` — strips the leading `/en/` (or other locale) from a Graph-returned path to produce the raw slug array.

## `getAllPagesPaths()`

```ts
// lib/optimizely/all-pages.ts
import { GraphClient } from '@optimizely/cms-sdk'
import { mapPathWithoutLocale } from './language'

const ALL_PAGES_QUERY = `
  query AllPages($pageType: [String]) {
    _Content(where: { _metadata: { types: { in: $pageType } } }) {
      items {
        _metadata {
          displayName
          url { base hierarchical default type }
        }
      }
    }
  }
`

export const getAllPagesPaths = async () => {
  try {
    const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
      graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
    })

    const pageTypes = ['CMSPage', 'SEOExperience']
    const pathsResp = await client.request(ALL_PAGES_QUERY, {
      pageType: pageTypes,
    } as any)

    const paths = (pathsResp._Content?.items as ContentItem[]) ?? []

    const filterPaths = paths.filter(
      (p) => p && p._metadata?.url?.default !== null,
    )

    const uniqueSlugs = new Set<string[]>()
    filterPaths.forEach((p) => {
      uniqueSlugs.add(mapPathWithoutLocale(p._metadata.url.default))
    })

    return Array.from(uniqueSlugs).map((slugArray) => ({ slug: slugArray }))
  } catch (e) {
    console.error('Error generating static params:', e)
    return []    // empty = ISR fallback
  }
}
```

Shape returned: `[{ slug: ['about'] }, { slug: ['blog', 'post-1'] }, ...]` — matches the `[...slug]` param's expected type (array of segments).

## Why filter by content type

Only `CMSPage` and `SEOExperience` pages have user-visible URLs. Everything else (`Header`, `Footer`, blocks, experiences-as-data) is fetched by path elsewhere and shouldn't be prerendered as its own route.

If you add a new page-level content type (e.g. `BlogArticlePage`), add its key to `pageTypes` — otherwise those pages will only render via ISR on first request, not at build time.

## `mapPathWithoutLocale`

```ts
// lib/optimizely/language.ts
export const DEFAULT_LOCALE = 'en'
export const LOCALES = ['en', 'pl', 'sv']

export const mapPathWithoutLocale = (path: string): string[] => {
  const parts = path.split('/').filter(Boolean)
  if (LOCALES.includes(parts[0] ?? '')) {
    parts.shift()
  }
  return parts
}
```

Converts `/en/blog/post-1/` → `['blog', 'post-1']`. Handles paths with or without leading locale, and collapses duplicate entries across locales via the `Set` in `getAllPagesPaths`.

## `generateStaticParams` wiring

```tsx
// app/[locale]/[...slug]/page.tsx
export async function generateStaticParams() {
  try {
    return await getAllPagesPaths()
  } catch (e) {
    console.error('Error generating static params:', e)
    return []
  }
}
```

Even though `getAllPagesPaths` already has internal try/catch, the wrapper here belts-and-braces against any unexpected throw during the build phase. **The build must never fail because the CMS is unreachable.** Returning `[]` means: "prerender nothing; rely on ISR to render each route on its first request."

For the root `[locale]/page.tsx` (homepage), the locale layout above provides `generateStaticParams` returning `LOCALES.map((locale) => ({ locale }))`. No per-slug logic needed at the homepage level.

## Locale layout's generateStaticParams

```tsx
// app/[locale]/layout.tsx
export function generateStaticParams() {
  try {
    return LOCALES.map((locale) => ({ locale }))
  } catch {
    return []
  }
}
```

This is what tells Next.js to pre-render a tree for each locale. Without it, only the default locale would prerender.

## Behaviour at build time

```
next build
├── Root layout evaluated → init.ts side-effect runs registrations
├── [locale]/layout generateStaticParams → [{locale:'en'},{locale:'pl'},{locale:'sv'}]
├── [locale]/[...slug] generateStaticParams → [{slug:['about']}, {slug:['blog','post-1']}, ...]
├── For each (locale, slug) pair:
│     Run page.tsx → calls getPageContent → fills cacheLife('max') cache entry → emits HTML
└── Bundle static HTML + cache state into .next/
```

At runtime, those cache entries survive until invalidated. A `revalidatePath(urlWithLocale)` from the webhook blows the cache entry; the next request re-runs `getPageContent` and re-caches.

## Behaviour when CMS is down during build

1. `generateStaticParams` returns `[]`
2. Build succeeds with zero prerendered pages for the `[...slug]` route
3. At runtime, each request first hits the catch-all, runs `getPageContent`, populates cache, serves HTML
4. Subsequent requests hit the cached entry

Net effect: the app works, but the first hit for each page is slower than if it had been prerendered.

## ISR revalidation on publish

When the CMS webhook fires (see `revalidation-webhook.md`):
- For regular pages → `revalidatePath(urlWithLocale)` → next request re-renders that page
- For header/footer → `revalidateTag(tag, 'max')` → every page re-renders its header/footer on next request

`revalidatePath` does not immediately regenerate the page — it marks the cache entry stale. The next in-flight request triggers the re-render.

## Adding new page types to static generation

When you add a new `_page` content type that should be prerendered:

1. Register the content type in `lib/optimizely/init.ts` (as always).
2. Add the key to `pageTypes` in `getAllPagesPaths`:
   ```ts
   const pageTypes = ['CMSPage', 'SEOExperience', 'BlogArticlePage']
   ```
3. If the new type lives under a different URL prefix and you want deep links to work at root level, ensure its URL generator in CMS is configured accordingly.

## Debugging "my page renders but isn't prerendered"

- Check `npm run build` output — the route tree shows which paths got static-generated. Paths not in the output are ISR-only.
- Check `getAllPagesPaths` returns your path — temporarily log the result.
- Check `mapPathWithoutLocale` isn't stripping something unexpectedly.
- Check the content type's `_metadata.url.default` isn't null in the Graph response (which would filter it out).
