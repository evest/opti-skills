---
name: optimizely-cms-nextjs
description: "Build the Next.js 16 application layer around @optimizely/cms-sdk v1.0.0 — App Router layouts, single init.ts registration entry, GraphClient fetching with 'use cache'/cacheLife/cacheTag, locale-aware middleware (proxy.ts), revalidation webhook (/api/revalidate) with SIMPLE vs hierarchical URL handling, preview route (/preview) with communicationinjector.js + PreviewComponent, Visual Builder rendering (OptimizelyComposition, OptimizelyGridSection, ComponentWrapper, getPreviewUtils with pa()), generateStaticParams via getAllPagesPaths, custom Cloudinary image loader, hreflang alternates, optimizely.config.mjs + opti-push CLI. Use when wiring up or modifying the Next.js app around an Optimizely SaaS CMS instance — layouts, caching strategy, revalidation, preview mode, locale routing, Visual Builder, ISR setup, image handling, SEO metadata. Complementary to the optimizely-cms-content-types skill (which covers contentType/displayTemplate schema authoring and property types); delegate property-type questions and schema design there. Do NOT use for CMS 12/PaaS (.NET), Commerce, Feature Experimentation, or non-Next.js frontends."
---

# Optimizely SaaS CMS + Next.js 16 Integration

How to wire up a Next.js 16 App Router application around `@optimizely/cms-sdk` v1.0.0. This skill covers the **app-integration layer** — schemas themselves live in the sister skill `optimizely-cms-content-types`.

## Critical Context

This is **Next.js 16** with React 19. Caching APIs (`'use cache'`, `cacheLife`, `cacheTag`) are not the Next.js 14 APIs. Always read `node_modules/next/dist/docs/` when an API's signature or behaviour seems uncertain, and check for deprecation notices.

The canonical reference implementation lives at `D:\Dev\uryga-nextjs\Optimizely-CMS-Content-SDK-Next.js-16\`. The official SDK docs live at `D:\Dev\content-js-sdk\docs\` (`1-installation.md` through `12-client-utils.md`).

## Trade-offs — When NOT to use this SDK

The SDK trades control for speed. Flag these up front when a user is considering the stack:

- **No fetch customization at the GraphQL layer.** You can't inject headers, set timeouts, or plug in retry logic around `GraphClient`'s requests — it's managed internally. If the project needs custom GraphQL middleware, this SDK is the wrong choice.
- **Global error interception from the rendering pipeline is hard.** `OptimizelyComponent` resolves and renders content internally; there's no clean hook to intercept every render error uniformly. Plan error-boundary strategy before committing.
- **Schema-in-code locks you in.** Editors can't freely add properties from the CMS UI without them immediately drifting from code. That's the point — but if your workflow expects editors to own the schema, this SDK inverts that assumption.
- **Not a fit for heavy composable-commerce / product-catalog use cases.** Combining CMS with PIM/commerce on the same SDK "creates more friction than it removes" — per the course author. Use dedicated commerce APIs alongside.

## The Dominant Failure Class: Silent Failures

Almost every wiring mistake in this stack produces **no error, no warning, just missing behaviour**. This is the single most important framing for debugging. See `references/troubleshooting.md` for the full silent-failure catalog; the headline cases:

| Mistake | Symptom |
|---|---|
| Component not in `initReactComponentRegistry` | Block renders blank, no log |
| Content type in code but file outside `components/optimizely/**/*.tsx` | `opti-push` skips it silently, CMS editor doesn't see it |
| Cache tag hardcoded instead of `getCacheTag(CACHE_KEYS.X, locale)` | Webhook's `revalidateTag` misses the fetcher's tag, content stays stale |
| `revalidateTag(tag)` without `'max'` second arg | No-op against `cacheLife('max')` entries |
| Webhook missing `bulk.completed` topic | Batch publishes don't invalidate |
| Webhook missing `status: { eq: "Published" }` filter | Draft saves spam revalidation and burn quota |
| Middleware not excluding `/preview` | Optimizely's preview params get rewritten, iframe breaks |
| `data-epi-edit="X"` doesn't match a property key | Click-to-edit disabled for that field only |
| Translation missing in CMS | Silently falls back to default locale |

Rule of thumb: if something isn't working and there's no error, the answer is in this table.

## Scope Split vs `optimizely-cms-content-types`

| Topic | This skill | content-types skill |
|---|---|---|
| `contentType()` schema definitions, property types, display templates | — | ✓ |
| `optimizely.config.mjs` + `buildConfig` | ✓ (wiring only) | ✓ (property groups) |
| `GraphClient` API surface reference | — | ✓ |
| `GraphClient` **usage in Next.js pages** with `'use cache'` | ✓ | — |
| `damAssets()` helpers | — | ✓ |
| `OptimizelyComponent` rendering, `OptimizelyComposition`, `OptimizelyGridSection` | ✓ | summary only |
| Preview route, webhook, locale middleware, static generation, ISR | ✓ | — |

When a user asks to author a new block/page/experience, do **both**: use content-types for the schema, this skill for the React component wrapper and registration.

## Canonical Architecture

```
app/
  layout.tsx                    — imports './globals.css' and '@/lib/optimizely/init'
  [locale]/
    layout.tsx                  — generateStaticParams returns LOCALES, renders <Header/><main/><Footer/>
    page.tsx                    — homepage; fetches '/{locale}/' with 'use cache'
    [...slug]/page.tsx          — catch-all; generateStaticParams calls getAllPagesPaths()
  api/revalidate/route.ts       — POST webhook; tag for header/footer, path for others
  preview/
    layout.tsx                  — no-cache Suspense shell
    page.tsx                    — getPreviewContent + PreviewComponent + communicationinjector.js

components/
  optimizely/
    block/ page/ experience/ section/    — one TSX per content type (schema + component co-located)
  layout/
    header.tsx footer.tsx language-switcher.tsx

lib/
  optimizely/
    init.ts                     — SINGLE entry point; runs all three registries at import time
    content-types.ts            — AllBlocksContentTypes list used in page schemas
    all-pages.ts                — getAllPagesPaths() — GraphQL query over CMSPage + SEOExperience
    language.ts                 — DEFAULT_LOCALE, LOCALES, mapPathWithoutLocale()
  cache/cache-keys.ts           — CACHE_KEYS + getCacheTag(key, locale)
  image/loader.ts               — 'use client' Cloudinary loader
  metadata.ts                   — generateAlternates(locale, path) for hreflang
  utils.ts                      — cn, createUrl, leadingSlashUrlPath

proxy.ts                        — middleware (note filename; see locale-routing.md)
next.config.ts                  — cacheComponents:true, custom image loader, CSP for preview
optimizely.config.mjs           — buildConfig({ components: ['./components/optimizely/**/*.tsx'] })
```

## The Five Rules That Matter Most

1. **Single init entry.** `app/layout.tsx` imports `@/lib/optimizely/init` (side-effect import). That file calls `initContentTypeRegistry([...])`, `initReactComponentRegistry({ resolver: {...} })`, and `initDisplayTemplateRegistry([...])` **in that order**. Every new content type must be added to BOTH `initContentTypeRegistry` AND `initReactComponentRegistry.resolver`.

2. **Page data fetchers use `'use cache'` + `cacheLife('max')`.** The directive must be the literal first statement in the async function body (not a comment, not after other code). Revalidation is driven by `cacheTag` / `revalidateTag` or `revalidatePath`, never by `cacheLife` expiry.

3. **Shared content (Header/Footer) wraps the fetch in `try/catch` INSIDE the `'use cache'` function and returns `null` on error.** Pages wrap the `await` call at the component level with `try { ... } catch { notFound() }`. The reason: during static prerender, an uncaught throw inside `'use cache'` surfaces as a `HANGING_PROMISE_REJECTION` that a component-level catch cannot intercept.

4. **Never hardcode cache tags.** Always `getCacheTag(CACHE_KEYS.HEADER, locale)` — and always pass `'max'` as the second arg to `revalidateTag()` when invalidating cacheLife('max') entries.

5. **Always render dynamic content via `OptimizelyComponent`.** Never switch on `__typename` manually. The SDK resolves the component via `initReactComponentRegistry`. For Visual Builder layouts use `OptimizelyComposition` / `OptimizelyGridSection` with custom `ComponentWrapper` / `row` / `column` that spread `{...pa(node)}`.

## Quick Reference — Canonical Code Shapes

### Root layout
```tsx
// app/layout.tsx
import '@/app/globals.css'
import '@/lib/optimizely/init'   // side-effect import registers all content types + components

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return <>{children}</>
}
```

### Locale layout
```tsx
// app/[locale]/layout.tsx
import { Header } from '@/components/layout/header'
import { Footer } from '@/components/layout/footer'
import { LOCALES } from '@/lib/optimizely/language'

export function generateStaticParams() {
  return LOCALES.map((locale) => ({ locale }))
}

export default async function LocaleLayout({
  children, params,
}: { children: React.ReactNode; params: Promise<{ locale: string }> }) {
  const { locale } = await params
  return (
    <html lang={locale}>
      <body>
        <Header locale={locale} />
        <main>{children}</main>
        <Footer locale={locale} />
      </body>
    </html>
  )
}
```

### Init file (single entry point)
```ts
// lib/optimizely/init.ts
import {
  BlankExperienceContentType,
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
} from '@optimizely/cms-sdk'
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server'

import HeroBlock, { HeroBlockContentType } from '@/components/optimizely/block/hero-block'
import CMSPage, { CMSPageContentType } from '@/components/optimizely/page/CMSPage'
import BlankExperience from '@/components/optimizely/experience/BlankExperience'
import BlankSection from '@/components/optimizely/section/BlankSection'
import ProfileBlock, {
  ProfileBlockContentType,
  ProfileBlockDisplayTemplate,
} from '@/components/optimizely/block/profile-block'

initContentTypeRegistry([
  HeroBlockContentType,
  ProfileBlockContentType,
  BlankExperienceContentType,    // built-in, re-registered here
  CMSPageContentType,
])

initReactComponentRegistry({
  resolver: {
    HeroBlock,
    ProfileBlock,
    CMSPage,
    BlankExperience,
    BlankSection,
  },
})

initDisplayTemplateRegistry([ProfileBlockDisplayTemplate])
```

### Homepage (root content)
```tsx
// app/[locale]/page.tsx
import { GraphClient } from '@optimizely/cms-sdk'
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server'
import { cacheLife } from 'next/cache'
import { notFound } from 'next/navigation'
import { generateAlternates } from '@/lib/metadata'
import type { Metadata } from 'next'

type Props = { params: Promise<{ locale: string }> }

async function getHomepageContent(locale: string) {
  'use cache'
  cacheLife('max')

  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })
  return client.getContentByPath(`/${locale}/`)
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params
  const [c] = await getHomepageContent(locale)
  return {
    title: c?.title ?? '',
    description: c?.shortDescription ?? '',
    keywords: c?.keywords ?? '',
    alternates: generateAlternates(locale, '/'),
  }
}

export default async function Page({ params }: Props) {
  const { locale } = await params
  try {
    const [c] = await getHomepageContent(locale)
    return <OptimizelyComponent content={c} />
  } catch (error) {
    console.error('Error fetching content:', error)
    return notFound()
  }
}
```

### Catch-all page
```tsx
// app/[locale]/[...slug]/page.tsx
export async function generateStaticParams() {
  try {
    return await getAllPagesPaths()   // returns [{ slug: ['about'] }, ...]
  } catch {
    return []                         // empty = fall back to on-demand ISR
  }
}

async function getPageContent(locale: string, slug: string[]) {
  'use cache'
  cacheLife('max')
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })
  return client.getContentByPath(`/${locale}/${slug.join('/')}/`)
}
```

### Shared content (Header/Footer) — try/catch INSIDE use cache
```tsx
// components/layout/header.tsx
import { GraphClient } from '@optimizely/cms-sdk'
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server'
import { cacheLife, cacheTag } from 'next/cache'
import { CACHE_KEYS, getCacheTag } from '@/lib/cache/cache-keys'

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
    return null   // never throw — HANGING_PROMISE_REJECTION during prerender
  }
}

export async function Header({ locale }: { locale: string }) {
  const content = await getHeaderContent(locale)
  if (!content) return null
  return <OptimizelyComponent content={content} />
}
```

### Block component
```tsx
// components/optimizely/block/hero-block.tsx
import { contentType, ContentProps } from '@optimizely/cms-sdk'

export const HeroBlockContentType = contentType({
  key: 'HeroBlock',
  displayName: 'Hero Block',
  baseType: '_component',
  properties: {
    title:    { type: 'string', displayName: 'Title',    localized: true },
    subtitle: { type: 'string', displayName: 'Subtitle', localized: true, sortOrder: 10 },
  },
})

type Props = { content: ContentProps<typeof HeroBlockContentType> }

export default function HeroBlock({ content: { title, subtitle } }: Props) {
  return (
    <section>
      <h1 data-epi-edit="title">{title}</h1>
      {subtitle && <p data-epi-edit="subtitle">{subtitle}</p>}
    </section>
  )
}
```

Always add `data-epi-edit="<propertyKey>"` to the rendered element for every editable property — this enables in-context editing inside the CMS preview iframe.

### Visual Builder Experience
```tsx
// components/optimizely/experience/BlankExperience.tsx
import { BlankExperienceContentType, ContentProps } from '@optimizely/cms-sdk'
import {
  ComponentContainerProps,
  OptimizelyComposition,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server'

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node)
  return <div {...pa(node)}>{children}</div>
}

export default function BlankExperience({
  content,
}: { content: ContentProps<typeof BlankExperienceContentType> }) {
  return (
    <main>
      <OptimizelyComposition
        nodes={content.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  )
}
```

### Visual Builder Section (grid)
```tsx
// components/optimizely/section/BlankSection.tsx
import { BlankSectionContentType, ContentProps } from '@optimizely/cms-sdk'
import {
  OptimizelyGridSection,
  StructureContainerProps,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server'

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node)
  return <div className="vb:row flex flex-col md:flex-row" {...pa(node)}>{children}</div>
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node)
  return <div className="vb:col flex flex-col" {...pa(node)}>{children}</div>
}

export default function BlankSection({
  content,
}: { content: ContentProps<typeof BlankSectionContentType> }) {
  const { pa } = getPreviewUtils(content)
  return (
    <section className="vb:grid relative flex w-full flex-col" {...pa(content)}>
      <OptimizelyGridSection nodes={content.nodes} row={Row} column={Column} />
    </section>
  )
}
```

The `vb:grid`, `vb:row`, `vb:col` classes are required — the Visual Builder UI targets them.

### Revalidation webhook (abbreviated — see revalidation-webhook.md)
```ts
// app/api/revalidate/route.ts
export async function POST(request: NextRequest) {
  try {
    // 1. Validate ?cg_webhook_secret=… against OPTIMIZELY_REVALIDATE_SECRET
    // 2. Read docId from body — format: "<guid>_<locale>_Published"
    //    Bail with 200 "No action taken" if docId lacks 'Published'
    // 3. Query Graph for the content using the guid (strip hyphens)
    // 4. Pick url: SIMPLE → _metadata.url.default
    //               hierarchical → _metadata.url.hierarchical, strip OPTIMIZELY_START_PAGE_URL prefix
    // 5. Normalize — leading slash, no trailing slash, prepend /{locale} if missing
    // 6. Revalidate:
    //      url includes 'footer' → revalidateTag(getCacheTag(CACHE_KEYS.FOOTER, locale), 'max')
    //      url includes 'header' → revalidateTag(getCacheTag(CACHE_KEYS.HEADER, locale), 'max')
    //      else                   → revalidatePath(urlWithLocale)
    return NextResponse.json({ revalidated: true, now: Date.now() })
  } catch (e) { /* return 401 for 'Invalid credentials', else 500 */ }
}
```

### Preview route
```tsx
// app/preview/page.tsx
import { GraphClient, type PreviewParams } from '@optimizely/cms-sdk'
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server'
import { PreviewComponent } from '@optimizely/cms-sdk/react/client'
import Script from 'next/script'
import { Suspense } from 'react'

export default async function Page({
  searchParams,
}: { searchParams: Promise<{ [key: string]: string | string[] | undefined }> }) {
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })
  const response = await client.getPreviewContent(
    (await searchParams) as PreviewParams,
  )
  if (!response) return <div>No content found.</div>

  return (
    <>
      <Script src={`${process.env.OPTIMIZELY_CMS_HOST}/util/javascript/communicationinjector.js`} />
      <PreviewComponent />
      <Suspense fallback={<div>Loading…</div>}>
        <OptimizelyComponent content={response} />
      </Suspense>
    </>
  )
}
```

Preview route must be excluded from locale middleware (see `locale-routing.md`).

### optimizely.config.mjs
```js
import { buildConfig } from '@optimizely/cms-sdk'

export default buildConfig({
  components: ['./components/optimizely/**/*.tsx'],
})
```

### package.json scripts
```json
{
  "scripts": {
    "opti-push":           "npx @optimizely/cms-cli@latest config push optimizely.config.mjs",
    "opti-push-data-loss": "npx @optimizely/cms-cli@latest config push optimizely.config.mjs --force"
  }
}
```

`opti-push-data-loss` (with `--force`) will drop CMS-side properties that no longer exist in code. Never run it without confirming the user wants destructive sync.

## Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `OPTIMIZELY_GRAPH_SINGLE_KEY` | yes (runtime) | Content Graph read key |
| `OPTIMIZELY_GRAPH_URL` | yes (runtime) | Usually `https://cg.optimizely.com/content/v2` |
| `OPTIMIZELY_CMS_HOST` | yes (preview + CLI) | e.g. `https://<instance>.cms.optimizely.com` |
| `OPTIMIZELY_CMS_CLIENT_ID` | yes (CLI) | For `opti-push` auth |
| `OPTIMIZELY_CMS_CLIENT_SECRET` | yes (CLI) | For `opti-push` auth |
| `OPTIMIZELY_REVALIDATE_SECRET` | yes (webhook) | Query-param shared secret; CMS webhook URL becomes `/api/revalidate?cg_webhook_secret=<value>` |
| `OPTIMIZELY_START_PAGE_URL` | yes if using hierarchical routing | e.g. `/start-page`; webhook strips this prefix |

## Imports cheat-sheet

```ts
// @optimizely/cms-sdk (main)
import {
  contentType, displayTemplate, ContentProps,
  GraphClient, buildConfig,
  initContentTypeRegistry, initDisplayTemplateRegistry,
  BlankExperienceContentType, BlankSectionContentType,
  type PreviewParams,
  damAssets,                       // see content-types skill
} from '@optimizely/cms-sdk'

// @optimizely/cms-sdk/react/server
import {
  initReactComponentRegistry,
  OptimizelyComponent,
  OptimizelyComposition,
  OptimizelyGridSection,
  getPreviewUtils,
  type ComponentContainerProps,
  type StructureContainerProps,
  withAppContext,                  // advanced; only if bypassing default context adapter
} from '@optimizely/cms-sdk/react/server'

// @optimizely/cms-sdk/react/client — use only inside /preview
import { PreviewComponent } from '@optimizely/cms-sdk/react/client'

// next/cache
import { cacheLife, cacheTag, revalidatePath, revalidateTag } from 'next/cache'
```

## Decision Tree — "I want to add/change X"

- **Add a new block/page/experience content type** → use `optimizely-cms-content-types` skill to design the schema, then: create the TSX co-locating the schema export + default-export React component, add to `lib/optimizely/init.ts` BOTH registries, add to `AllBlocksContentTypes` in `lib/optimizely/content-types.ts` if it should be placeable inside `CMSPage.blocks`, run `npm run opti-push`.
- **Fix stale header/footer after CMS publish** → verify the webhook hits `revalidateTag(getCacheTag(CACHE_KEYS.HEADER, locale), 'max')` with `'max'` as the 2nd arg (NOT just `revalidateTag(tag)`).
- **Add a new locale** → extend `LOCALES` in `lib/optimizely/language.ts`, extend `LOCALE_NAMES` in the language-switcher, add the language in CMS settings. No middleware changes needed — Negotiator will pick it up.
- **Add CMS preview support** → confirm `/preview/layout.tsx` + `/preview/page.tsx` exist, confirm middleware excludes `/preview`, confirm `OPTIMIZELY_CMS_HOST` is set, verify `next.config.ts` CSP allows `frame-ancestors 'self' *.optimizely.com`.
- **Prerender all pages at build** → ensure `generateStaticParams` in `[...slug]/page.tsx` calls `getAllPagesPaths()`. If the build can't reach CMS, that function returns `[]` and ISR picks up on demand — the build still succeeds.
- **Show draft content on /preview but published elsewhere** → the `/preview` route uses `client.getPreviewContent(searchParams as PreviewParams)`, not `getContentByPath`. Don't try to unify them.
- **Support a second variation** → pass `variation: { include: 'SOME', value: [...] }` to `getContentByPath`.
- **Handle a new Cloudinary-hosted image** → the custom loader at `lib/image/loader.ts` handles it automatically for any `res.cloudinary.com` src; just use `next/image` normally.

## Critical gotchas (quick list)

- `'use cache'` MUST be the first line of the function body. Comments above are fine, code is not.
- `revalidateTag(tag)` without `'max'` as 2nd arg silently fails to invalidate `cacheLife('max')` entries.
- `proxy.ts` is middleware despite the non-standard filename — the `proxy` named export and `config.matcher` export make it work. Do not rename to `middleware.ts` if the rest of the repo expects `proxy.ts` (Next.js supports either by config).
- The catch-all `[...slug]` page tries to fetch `/${locale}/${slug.join('/')}/` with a trailing slash — matches how Optimizely's Content Graph indexes URLs. Don't strip it.
- The webhook's `docId` format is `<UUID-with-dashes>_<locale>_Published`. You must `replaceAll('-', '')` before querying Graph.
- For hierarchical URL routing, the Start Page's URL is NOT `/` — it's something like `/start-page`. The webhook strips `OPTIMIZELY_START_PAGE_URL` to normalize. If you forget this env var, every page revalidates at `/start-page/*` instead of `/*`.
- `next.config.ts` sets `cacheComponents: true` — required for `'use cache'` to work in server components.
- `next.config.ts` sets a CSP header `frame-ancestors 'self' *.optimizely.com` — required for the CMS to embed the site in its preview iframe. Drop this and preview breaks silently.
- The image loader file is `'use client'`. Do not add server-only imports to it.
- The `OptimizelyComponent` type signature doesn't formally accept extra props like `locale`; pass via `as React.ComponentType<{content: any; locale: string}>` cast (see the example repo's `header.tsx` line 27-33). This is a known SDK types limitation.

## References

- `references/project-setup.md` — Full `next.config.ts`, `tsconfig.json`, `optimizely.config.mjs`, `package.json`, env file template, dependency pins
- `references/registration.md` — `init.ts` ordering rules, resolver variants (tag, function form), what breaks if a type is unregistered
- `references/data-fetching.md` — `'use cache'` deep dive, `cacheLife` values, tag vs path revalidation strategy, GraphClient method usage, variation filtering
- `references/static-generation.md` — `getAllPagesPaths` GraphQL query, ISR fallback behaviour, build-time failure recovery
- `references/locale-routing.md` — Full `proxy.ts` walkthrough, rewrite vs redirect semantics, Negotiator integration, `generateAlternates` (hreflang), cookie vs header precedence
- `references/revalidation-webhook.md` — Full `route.ts` recipe, docId parsing, SIMPLE vs hierarchical URL resolution, error response contract
- `references/preview-mode.md` — Preview route setup, `PreviewComponent` lifecycle, `communicationinjector.js`, `getPreviewContent` params, Suspense usage
- `references/visual-builder.md` — `OptimizelyComposition`/`OptimizelyGridSection` node contracts, `ComponentWrapper`/`row`/`column` props, `getPreviewUtils.pa()` vs `src()`, `vb:` classes, `compositionBehaviors`
- `references/image-handling.md` — Custom Cloudinary loader walkthrough, remote patterns, SVG exclusion, adding new CDN hosts
- `references/troubleshooting.md` — Symptom-indexed common errors and fixes

## Authoritative sources

- Example implementation: `D:\Dev\uryga-nextjs\Optimizely-CMS-Content-SDK-Next.js-16\`
- Official SDK source + docs: `D:\Dev\content-js-sdk\` (especially `docs/1-installation.md` through `docs/12-client-utils.md`)
- Official CLI docs: https://github.com/episerver/content-js-sdk/blob/main/docs/1-installation.md
- Companion skill: `optimizely-cms-content-types`
