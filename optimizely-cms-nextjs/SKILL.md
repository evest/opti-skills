---
name: optimizely-cms-nextjs
description: "Build the Next.js 16 application layer around @optimizely/cms-sdk v2 — App Router layouts, single src/optimizely.ts registration entry with config()+getClient(), withAppContext-wrapped catch-all + preview, 'use cache' / cacheLife / cacheTag for ISR, next-intl locale routing via src/proxy.ts middleware, /hooks/graph webhook with x-api-key auth + CDN purge, Visual Builder rendering (OptimizelyComposition, OptimizelyGridSection, ComponentWrapper, getPreviewUtils.pa()/src()), shared Redis cache handler for DXP, sitemap and robots, SEO metadata extraction. Use when wiring up or modifying the Next.js app around an Optimizely SaaS CMS instance — layouts, caching strategy, revalidation webhook, preview mode, locale routing, Visual Builder shell, ISR setup, image handling, SEO metadata, DXP-specific infrastructure. Complementary to the optimizely-cms-content-types skill (which covers contentType/displayTemplate schema authoring, property types, and the in-component pattern); delegate property-type questions and schema design there. Do NOT use for CMS 12/PaaS (.NET), Commerce catalog, Feature Experimentation, or non-Next.js frontends."
---

# Optimizely SaaS CMS + Next.js 16 Integration (SDK v2)

How to wire up a Next.js 16 App Router application around `@optimizely/cms-sdk` v2. This skill covers the **app-integration layer** — schemas themselves live in the sister skill `optimizely-cms-content-types`.

## Stack assumptions

- **Next.js 16** with React 19 and `cacheComponents: true` (auto-PPR). The `'use cache'` / `cacheLife` / `cacheTag` APIs are the Next.js 16 shape — not the Next.js 14 fetch-cache shape.
- **@optimizely/cms-sdk v2** with `config()` + `getClient()` as the canonical pattern; `new GraphClient()` still works but is no longer preferred.
- **next-intl** for locale routing (middleware via `src/proxy.ts` using `createMiddleware(routing)`). No bespoke locale negotiation.
- **Optimizely DXP / Frontend Hosting** for deployment, with the Optimizely shared Redis cache handler (`cache-handler.mjs`) acting as the source of truth across replicas.

If the project doesn't match those assumptions, much of this skill still applies — but pause and surface the divergence before applying patterns blindly.

## v2 in 30 seconds

If you've worked with this stack on SDK v1, the deltas:
- **Recommended fetching**: call `config({ apiKey, graphUrl, ... })` once at app entry; everywhere else use `getClient()`. `new GraphClient()` still works but no project should construct it per-call any more.
- **`withAppContext(Page)`**: required HOC for catch-all + preview routes. Initialises request-scoped context that `getPreviewContent` populates (`preview_token`, `key`, `locale`, `version`, `mode`). Components read via `getContextData('preview_token' | …)`.
- **`getContent(GraphReference)`**: new method on the client. Accepts `{ key, locale?, version? }` or a `graph://` string. `getPath`/`getItems` also accept GraphReference.
- **Canonical prop name** in components is `content` (not `opti`). Old v1 codebases use `opti`.
- **`maxFragmentThreshold`** warning at runtime if a content type generates too many GraphQL inner fragments — usually means a `content`/`contentReference` property is missing `allowedTypes`. Configure via `config({ maxFragmentThreshold: 150 })` only as a last resort.

Detailed schema rules and per-property concerns live in the `optimizely-cms-content-types` skill.

## The Dominant Failure Class: Silent Failures

Almost every wiring mistake in this stack produces **no error, no warning, just missing behaviour**. This is the single most important framing for debugging. Full catalog in `references/troubleshooting.md`; the headline cases:

| Mistake | Symptom |
|---|---|
| Component not in `initReactComponentRegistry` | Block renders blank, no log |
| Content type in code but file not matched by `optimizely.config.mjs` `components` glob | `npm run cms:push-config` skips it silently, CMS editor doesn't see it |
| `BlankSectionContentType` referenced in CMS content but not in `initContentTypeRegistry` | Visual Builder content renders blank |
| `cacheTag(getPageTag(slug))` mismatched with webhook's `revalidateTag(getPageTag(...))` | Webhook fires, but tag doesn't match, content stays stale |
| `revalidateTag(tag)` without `'max'` second arg | No-op against `cacheLife('max')` entries |
| Webhook missing `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` env var | `x-api-key` check rejects every request; webhook silently does nothing in prod |
| Middleware matcher not excluding `/preview` | next-intl wraps preview URL, breaks CMS iframe params |
| `notFound()` thrown from inside `<Suspense>` under cacheComponents | Returns 200 OK with notfound body, CDN caches for 30 days |
| Preview route missing `withAppContext` wrapper | `getContextData` returns nothing; `RichText` images miss preview tokens |
| Catch-all `[[...slug]]` includes a real slug `__no-cms-pages-at-build__` | Should never happen unless an editor created that exact slug |

Rule of thumb: if something isn't working and there's no error, the answer is in this table.

## Scope Split vs `optimizely-cms-content-types`

| Topic | This skill | content-types skill |
|---|---|---|
| `contentType()` schema definitions, property types, display templates | — | ✓ |
| `optimizely.config.mjs` + `buildConfig` | ✓ (wiring only) | ✓ (property groups, glob negation) |
| `GraphClient` / `getClient` API reference | summary only | ✓ |
| `GraphClient` usage in Next.js pages with `'use cache'` | ✓ | — |
| `damAssets()` helpers | — | ✓ |
| `RichText` component API (custom elements/leafs) | — | ✓ |
| `OptimizelyComponent`, `OptimizelyComposition`, `OptimizelyGridSection` rendering | ✓ | summary only |
| `getPreviewUtils` (`pa`, `src`), `data-epi-*` attributes | summary | ✓ |
| Preview route, webhook, locale middleware, static generation, ISR, cache handler | ✓ | — |

When a user asks to author a new block/page/experience, do **both**: use content-types for the schema, this skill for the React component wrapper, registration, and route wiring.

## Canonical Architecture (`D:\Dev\nextjs-fe-hosting`)

```
src/
  app/
    layout.tsx                       — imports './globals.css' and '@/optimizely' (side-effect)
    [locale]/
      layout.tsx                     — generateStaticParams from routing.locales; renders <Header/><main/><Footer/> inside <NextIntlClientProvider/>
      [[...slug]]/page.tsx           — optional catch-all (matches locale root + nested); withAppContext(Page); calls notFound() outside Suspense
    preview/page.tsx                 — withAppContext(Page); getPreviewContent(); PreviewComponent + communicationinjector.js; retry on "No content found for key"
    hooks/graph/route.ts             — POST webhook; x-api-key auth; revalidatePath + ancestor-tag invalidation + CDN purge
    sitemap.ts                       — calls getAllContentPaths() (cached + tagged)
    robots.ts                        — disallows /preview, /diagnostics, /debug, /hooks/
    diagnostics/ debug/              — dev-only inspection routes (excluded from middleware + robots)

  components/
    pages/ blocks/ elements/ experiences/ layout/ ui/
    layout/CommunicationInjector.tsx   — 'use client' wrapper for the CMS injector script (only used in /preview)
    layout/PreviewError.tsx            — renders structured SDK error info with copy-to-clipboard

  content-types/                     — contentType() definitions (see content-types skill)
  display-templates/                 — displayTemplate() definitions

  lib/
    optimizely/
      get-page.ts                    — getPageContent(slug) — 'use cache' + cacheLife('max') + cacheTag(getPageTag(slug))
      all-pages.ts                   — getAllPagesPaths() — returns placeholder per locale (no build-time prerender)
      all-content-paths.ts           — getAllContentPaths() for sitemap; cacheTag(CACHE_KEYS.PATHS)
      get-articles-under.ts          — listing pattern with ancestor-prefix tag invalidation
      navigation.ts                  — re-exports from next-intl/navigation
    cache/
      cache-keys.ts                  — CACHE_KEYS const + getPageTag/getArticlesUnderTag composers
    cdn-cache.ts                     — purgeCdnCache() via Cloud Platform Services API (managed identity)
    config.ts                        — getGraphGatewayUrl() helper for local-vs-DXP env shape
    seo.ts                           — getSeoMetadata() from CMS SeoBlock + canonical URL emission
    rich-text.ts                     — decodeRichTextEntities() helper

  i18n/
    routing.ts                       — defineRouting({ locales, defaultLocale, localePrefix: 'always' })
    request.ts                       — getRequestConfig with messages/<locale>.json
    navigation.ts                    — createNavigation(routing) — locale-aware <Link>, redirect, etc.

  optimizely.ts                      — SDK init entry: config(), initContentTypeRegistry, initDisplayTemplateRegistry, initReactComponentRegistry
  proxy.ts                           — createMiddleware(routing); matcher excludes api/hooks/debug/diagnostics/preview/_next/_vercel/static files

cache-handler.mjs                    — shared Redis cache handler (DXP-aware, Entra ID auth, in-memory fallback)
optimizely.config.mjs                — buildConfig({ components: [...file paths...] })
next.config.ts                       — cacheComponents:true, cacheHandler path, image remotePatterns, withNextIntl plugin
messages/
  en.json no.json sv.json da.json    — next-intl translations
```

## The Six Rules That Matter Most

1. **Single init entry.** `app/layout.tsx` imports `@/optimizely` (side-effect import). That file calls `config(...)`, `initContentTypeRegistry([...])`, `initDisplayTemplateRegistry([...])`, and `initReactComponentRegistry({ resolver: {...} })` — **in that order**. Every new content type must be added to BOTH `initContentTypeRegistry` AND `initReactComponentRegistry.resolver`. Built-in `BlankExperienceContentType` / `BlankSectionContentType` are NOT auto-registered.

2. **Page fetchers use `'use cache'` + `cacheLife('max')` + `cacheTag(getPageTag(slug))`.** The directive must be the literal first statement in the async function body (not after other code, not after a `try`). Revalidation is driven by `cacheTag` / `revalidateTag` or `revalidatePath`, never by `cacheLife` expiry.

3. **`notFound()` must be called outside `<Suspense>` AND in `generateMetadata`** under `cacheComponents`. The response status commits when the static shell flushes; a `notFound()` thrown from inside a suspended child swaps the body but not the status, so unknown URLs would serve `200 OK` with a 30-day CDN cache.

4. **Never let a `'use cache'` function throw.** Wrap external calls in `try/catch`, return `null` on error. A throw during prerender surfaces as `HANGING_PROMISE_REJECTION` that component-level try/catch can't intercept.

5. **Always pair `cacheTag(getPageTag(slug))` with `revalidateTag(getPageTag(slug), 'max')`** in the webhook. The `'max'` second arg matches the `cacheLife('max')` profile — without it the invalidation is silently dropped against long-lived entries.

6. **Always render dynamic content via `OptimizelyComponent`.** Never switch on `__typename` manually. The SDK resolves the component via `initReactComponentRegistry`. For Visual Builder layouts use `OptimizelyComposition` / `OptimizelyGridSection` with custom `ComponentWrapper` / `row` / `column` that spread `{...pa(node)}`.

## Quick Reference — Canonical Code Shapes

### Root layout
```tsx
// src/app/layout.tsx
import './globals.css';
import '@/optimizely';  // side-effect import: runs config() + all three registries

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html suppressHydrationWarning>
      <body className="min-h-screen flex flex-col">{children}</body>
    </html>
  );
}
```

### Init file (single entry point)
```ts
// src/optimizely.ts
import {
  config,
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';
import * as contentTypes from '@/content-types';
import * as displayTemplates from '@/display-templates';
import * as components from '@/components';
import { getGraphGatewayUrl } from '@/lib/config';

// 1. Configure the Graph client once. getClient() reads from this config.
if (process.env.OPTIMIZELY_GRAPH_SINGLE_KEY) {
  config({
    apiKey: process.env.OPTIMIZELY_GRAPH_SINGLE_KEY,
    graphUrl: getGraphGatewayUrl(),
  });
}

// 2. Register every content type referenced in CMS content.
initContentTypeRegistry([
  ...Object.values(contentTypes),
  BlankExperienceContentType,
  BlankSectionContentType,
]);

// 3. Register display templates.
initDisplayTemplateRegistry([...Object.values(displayTemplates)]);

// 4. Map content type keys to React components.
initReactComponentRegistry({
  resolver: {
    ArticlePage: components.ArticlePage,
    HeroBlock: components.HeroBlock,
    BlankExperience: components.BlankExperience,
    BlankSection: components.BlankSection,
    // ... every key the CMS could resolve must appear here
  },
});
```

### Locale layout
```tsx
// src/app/[locale]/layout.tsx
import { notFound } from 'next/navigation';
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { Header, Footer } from '@/components/layout';
import { routing } from '@/i18n/routing';

type Props = {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: Props) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);

  return (
    <NextIntlClientProvider>
      <Header />
      <main id="main-content" className="flex-1">{children}</main>
      <Footer />
    </NextIntlClientProvider>
  );
}
```

### Catch-all page (handles locale root + nested)
```tsx
// src/app/[locale]/[[...slug]]/page.tsx
import type { Metadata } from 'next';
import { Suspense } from 'react';
import { OptimizelyComponent, withAppContext } from '@optimizely/cms-sdk/react/server';
import { notFound } from 'next/navigation';
import { hasLocale } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { getPageContent } from '@/lib/optimizely/get-page';
import { getAllPagesPaths } from '@/lib/optimizely/all-pages';
import { getSeoMetadata } from '@/lib/seo';
import { routing } from '@/i18n/routing';

type Props = { params: Promise<{ locale: string; slug?: string[] }> };

export async function generateStaticParams() {
  return getAllPagesPaths();
}

function fullSlug(locale: string, slug?: string[]): string[] {
  return [locale, ...(slug ?? [])];
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale, slug } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  const content = await getPageContent(fullSlug(locale, slug));
  if (!content) notFound();
  return getSeoMetadata(content as Record<string, unknown>);
}

function PageContent({ content }: { content: NonNullable<Awaited<ReturnType<typeof getPageContent>>> }) {
  return <OptimizelyComponent content={content} />;
}

async function Page({ params }: Props) {
  const { locale, slug } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);

  const content = await getPageContent(fullSlug(locale, slug));
  if (!content) notFound();   // MUST be outside <Suspense> — see Rule #3

  return (
    <Suspense>
      <PageContent content={content} />
    </Suspense>
  );
}

export default withAppContext(Page);
```

`[[...slug]]` (double brackets) is an optional catch-all — it matches both `/no/` (no slug) and `/no/about/` (slug `['about']`). Single-bracket `[...slug]` would NOT match the locale root.

### Page fetcher
```ts
// src/lib/optimizely/get-page.ts
import { getClient } from '@optimizely/cms-sdk';
import { cacheLife, cacheTag } from 'next/cache';
import { getPageTag } from '@/lib/cache/cache-keys';
import { PLACEHOLDER_SLUG_SEGMENT } from '@/lib/optimizely/all-pages';

export async function getPageContent(slug: string[]) {
  'use cache';
  cacheLife('max');
  cacheTag(getPageTag(slug));

  if (slug.includes(PLACEHOLDER_SLUG_SEGMENT)) {
    return null;   // short-circuit the build-time placeholder
  }

  try {
    const client = getClient();
    const path = `/${slug.join('/')}/`;
    const items = await client.getContentByPath(path);
    return items?.[0] ?? null;
  } catch (e) {
    console.error('[get-page] graph lookup failed:', e);
    return null;   // never throw under 'use cache' — see Rule #4
  }
}
```

### Static generation (placeholder pattern)
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

Cache Components requires `generateStaticParams` to return ≥1 entry. We return a placeholder per locale; `getPageContent` recognises it and short-circuits without a Graph call. Real pages are filled into the Redis cache on first request and survive across replicas. Rationale and trade-offs in `references/static-generation.md`.

### Preview route
```tsx
// src/app/preview/page.tsx
import { Suspense } from 'react';
import { getClient, type PreviewParams } from '@optimizely/cms-sdk';
import { OptimizelyComponent, withAppContext } from '@optimizely/cms-sdk/react/server';
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { routing } from '@/i18n/routing';
import { Header, Footer } from '@/components/layout';
import PreviewError from '@/components/layout/PreviewError';
import Script from 'next/script';

type Props = {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
};

async function PreviewBody({ searchParams }: Props) {
  const params = await searchParams;

  // Bridge CMS-supplied `loc` into next-intl so translations resolve inside
  // rendered components.
  const locParam = typeof params.loc === 'string' ? params.loc : undefined;
  const locale = hasLocale(routing.locales, locParam) ? locParam : routing.defaultLocale;
  setRequestLocale(locale);
  const messages = (await import(`../../../messages/${locale}.json`)).default;

  const client = getClient();
  let response;
  let error: unknown = null;

  // Retry pattern: editor publishes can briefly precede Graph indexing.
  for (let attempt = 0; attempt <= 3; attempt++) {
    try {
      error = null;
      response = await client.getPreviewContent(params as PreviewParams);
      break;
    } catch (err: unknown) {
      error = err;
      const notYetIndexed =
        err instanceof Error && err.message.includes('No content found for key');
      if (notYetIndexed && attempt < 3) {
        await new Promise((r) => setTimeout(r, 200));
        continue;
      }
      break;
    }
  }

  if (error) {
    return (
      <NextIntlClientProvider locale={locale} messages={messages}>
        <Header />
        <main className="flex-1"><PreviewError error={error} params={params} /></main>
        <Footer />
      </NextIntlClientProvider>
    );
  }

  return (
    <NextIntlClientProvider locale={locale} messages={messages}>
      <Header />
      <main className="flex-1"><OptimizelyComponent content={response} /></main>
      <Footer />
    </NextIntlClientProvider>
  );
}

function Page({ searchParams }: Props) {
  return (
    <div className="flex-1 flex flex-col">
      <Script
        src={`${process.env.OPTIMIZELY_CMS_URL}/util/javascript/communicationinjector.js`}
        strategy="beforeInteractive"
        id="optimizely-communication-injector"
      />
      <PreviewComponent />
      <Suspense>
        <PreviewBody searchParams={searchParams} />
      </Suspense>
    </div>
  );
}

export default withAppContext(Page);
```

The `withAppContext(Page)` wrap is what makes `getContextData('preview_token' | 'locale' | …)` work inside nested components — `getPreviewContent` populates the context, and helpers like `RichText` and `getPreviewUtils.src()` read it automatically for image preview tokens.

### Webhook (`/hooks/graph`)
```ts
// src/app/hooks/graph/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { revalidatePath, revalidateTag } from 'next/cache';
import { purgeCdnCache } from '@/lib/cdn-cache';
import { CACHE_KEYS, getArticlesUnderTag } from '@/lib/cache/cache-keys';

const CALLBACK_API_KEY = process.env.OPTIMIZELY_GRAPH_CALLBACK_APIKEY;
const singleKey = process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!;
const gateway = (process.env.OPTIMIZELY_GRAPH_GATEWAY ?? 'https://cg.optimizely.com').replace(/\/+$/, '');
const graphUrl = `${gateway}/content/v2`;

async function graphRequest(query: string, variables: Record<string, unknown>) {
  const res = await fetch(graphUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `epi-single ${singleKey}`,
    },
    body: JSON.stringify({ query, variables }),
  });
  if (!res.ok) throw new Error(`GraphQL request failed (${res.status})`);
  const json = await res.json();
  return json.data;
}

async function revalidateDocId(docId: string): Promise<string> {
  const [rawId, locale] = docId.split('_');
  const id = rawId.replaceAll('-', '');
  const response = await graphRequest(
    `query GetPath($id: String, $locale: Locales) {
       _Content(ids: [$id], locale: [$locale]) {
         item { _metadata { url { default } } }
       }
     }`,
    { id, locale },
  );
  const url = response?._Content?.item?._metadata?.url?.default;
  if (!url) return '';
  const path = url.endsWith('/') ? url.slice(0, -1) : url;
  revalidatePath(path || '/');

  // Invalidate every ancestor article-listing cache (cheap; over-invalidates safely).
  const segments = path.split('/').filter(Boolean);
  for (let i = 1; i < segments.length; i++) {
    const parent = `/${segments.slice(0, i).join('/')}/`;
    revalidateTag(getArticlesUnderTag(parent, locale), 'max');
  }

  // Sitemap is tagged with PATHS; invalidate so the new URL surfaces.
  revalidateTag(CACHE_KEYS.PATHS, 'hours');
  return path || '/';
}

export async function POST(request: NextRequest) {
  const apiKey = request.headers.get('x-api-key');
  if (!CALLBACK_API_KEY || apiKey !== CALLBACK_API_KEY) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const payload = await request.json();
  const { subject, action } = payload.type;
  if (subject === 'doc' && (action === 'updated' || action === 'expired')) {
    const path = await revalidateDocId(payload.data.docId);
    if (path) {
      const hostname = process.env.OPTIMIZELY_SITE_HOSTNAME?.replace(/^https?:\/\//, '');
      if (hostname) {
        purgeCdnCache([`https://${hostname}${path}`]).catch((err) =>
          console.error('[hooks] CDN cache purge failed:', err.message),
        );
      }
    }
  }
  return NextResponse.json({ received: true });
}
```

Note the auth: `x-api-key` header (not query-param secret). Always returns 200 so Optimizely doesn't retry on transient downstream failures.

### Visual Builder Experience
```tsx
// src/components/experiences/BlankExperience.tsx
import { BlankExperienceContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  ComponentContainerProps,
  OptimizelyComposition,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';

type Props = { content: ContentProps<typeof BlankExperienceContentType> };

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="mb-2" {...pa(node)}>{children}</div>;
}

export default function BlankExperience({ content }: Props) {
  return (
    <main>
      <OptimizelyComposition
        nodes={content.composition?.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

### Visual Builder Section (grid)
```tsx
// src/components/experiences/BlankSection.tsx — abbreviated
import { BlankSectionContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  OptimizelyGridSection,
  StructureContainerProps,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="vb:row flex flex-row" {...pa(node)}>{children}</div>;
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="vb:col flex-1 flex flex-col" {...pa(node)}>{children}</div>;
}

type Props = { content: ContentProps<typeof BlankSectionContentType> };

export default function BlankSection({ content }: Props) {
  const { pa } = getPreviewUtils(content);
  return (
    <section className="vb:grid relative w-full" {...pa(content)}>
      <OptimizelyGridSection nodes={content.nodes} row={Row} column={Column} />
    </section>
  );
}
```

`vb:grid`, `vb:row`, `vb:col` are required marker classes the Visual Builder UI targets — keep them. Row/column display templates expose `displaySettings` through `StructureContainerProps`; see `references/visual-builder.md` and the content-types skill.

### Middleware
```ts
// src/proxy.ts
import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';

export default createMiddleware(routing);

export const config = {
  matcher: [
    // Match everything except API routes, webhook receivers, dev tools,
    // preview, Next.js internals, and static files.
    '/((?!api|hooks|debug|diagnostics|preview|_next|_vercel|.*\\..*).*)',
  ],
};
```

`src/proxy.ts` is recognised by Next.js as middleware via the `proxy` default export + `config` named export. Filename doesn't need to be `middleware.ts`.

### `optimizely.config.mjs`
```js
// optimizely.config.mjs
import { buildConfig } from '@optimizely/cms-sdk';

export default buildConfig({
  components: [
    './src/content-types/ArticlePage.ts',
    './src/content-types/HeroBlock.ts',
    // ... or use a glob:
    // './src/content-types/**/*.ts',
    // './src/display-templates/**/*.ts',
  ],
  propertyGroups: [
    { key: 'media', displayName: 'Media', sortOrder: 200 },
    { key: 'seo', displayName: 'SEO', sortOrder: 300 },
  ],
});
```

See the content-types skill for property-group rules and glob negation patterns.

### `package.json` scripts (pin major version)
```json
{
  "scripts": {
    "dev": "next dev --experimental-https",
    "build": "next build",
    "start": "next start",
    "cms:login": "npx @optimizely/cms-cli@^2.0.0 login",
    "cms:push-config": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs",
    "cms:push-config-force": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs --force",
    "cms:pull-config": "npx @optimizely/cms-cli@^2.0.0 config pull --output ./src/content-types --group"
  }
}
```

`cms:push-config-force` (with `--force`) will drop CMS-side properties that no longer exist in code. Never run without confirming the user wants destructive sync.

## Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `OPTIMIZELY_GRAPH_SINGLE_KEY` | yes (runtime) | Content Graph read key. From CMS → Settings → API Keys → Render Content |
| `OPTIMIZELY_GRAPH_GATEWAY` | yes (runtime) | Locally `https://cg.optimizely.com/content/v2`; in DXP just `https://cg.optimizely.com` (path appended by `getGraphGatewayUrl()`) |
| `OPTIMIZELY_GRAPH_PATH` | no | Override path; defaults to `/content/v2` |
| `OPTIMIZELY_CMS_URL` | yes (preview) | e.g. `https://<instance>.cms.optimizely.com` — used in `communicationinjector.js` URL |
| `OPTIMIZELY_CMS_CLIENT_ID` | yes (CLI) | For `cms:push-config` auth |
| `OPTIMIZELY_CMS_CLIENT_SECRET` | yes (CLI) | For `cms:push-config` auth |
| `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` | yes (webhook) | Shared secret sent as `x-api-key` header by Optimizely |
| `OPTIMIZELY_SITE_HOSTNAME` | required for CDN purge | Public hostname (e.g. `mysite.example.com`) used to construct purge URLs |
| `NEXT_PUBLIC_SITE_URL` | yes (SEO/sitemap) | Origin (no trailing slash) for canonical URLs + sitemap entries |
| `OPTIMIZELY_WEB_EXP_SNIPPET_ID` | optional | Optimizely Web Experimentation snippet ID; leave blank to skip |
| `REDIS_URL` | DXP only | `host:port` for shared Redis (Frontend Hosting provisions this) |
| `OPTIMIZELY_DXP_DEPLOYMENT_ID` | DXP only | Used to namespace cache keys per deployment |
| `AZURE_CLIENT_ID` | DXP only | Managed-identity client ID for Redis + CDN auth |
| `OPTIMIZELY_CLOUDPLATFORM_API_URL` | DXP only (CDN purge) | Cloud Platform Services edge-cache API endpoint |
| `OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID` | DXP only (CDN purge) | Resource ID for managed-identity token scope |
| `OPTI_PROJECT_ID`, `OPTI_CLIENT_KEY`, `OPTI_CLIENT_SECRET`, `OPTI_TARGET_ENV` | for `deploy.ps1` | From PaaS Portal → API tab → Deployment API Credentials |

All `OPTIMIZELY_GRAPH_GATEWAY`, `REDIS_URL`, `OPTIMIZELY_DXP_DEPLOYMENT_ID`, `AZURE_CLIENT_ID`, and the Cloud Platform vars are **auto-provisioned by Frontend Hosting** at deploy time. Locally, leave them blank to skip Redis (in-memory fallback) and CDN purge (no-op).

## Imports cheat-sheet

```ts
// @optimizely/cms-sdk (main)
import {
  contentType, displayTemplate, ContentProps,
  config, getClient,                 // v2 recommended fetching pattern
  GraphClient,                       // still supported, but prefer config+getClient
  buildConfig,
  initContentTypeRegistry, initDisplayTemplateRegistry,
  BlankExperienceContentType, BlankSectionContentType,
  type PreviewParams,
  damAssets,                         // see content-types skill
} from '@optimizely/cms-sdk';

// @optimizely/cms-sdk/react/server
import {
  initReactComponentRegistry,
  OptimizelyComponent,
  OptimizelyComposition,
  OptimizelyGridSection,
  getPreviewUtils,
  withAppContext,                    // REQUIRED HOC for catch-all + preview
  getContext, getContextData, setContext,
  type ComponentContainerProps,
  type StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';

// @optimizely/cms-sdk/react/client — only inside /preview
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';

// @optimizely/cms-sdk/react/richText — see content-types skill
import { RichText } from '@optimizely/cms-sdk/react/richText';

// next/cache
import { cacheLife, cacheTag, revalidatePath, revalidateTag } from 'next/cache';

// next-intl
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { Link, redirect, usePathname, useRouter } from '@/i18n/navigation';
```

## Decision Tree — "I want to add/change X"

- **Add a new block/page/experience content type** → use the `optimizely-cms-content-types` skill to design the schema. Create the TSX co-locating the schema export + default-export React component. Add to BOTH `initContentTypeRegistry` AND `initReactComponentRegistry.resolver` in `src/optimizely.ts`. Add the file path to `components` in `optimizely.config.mjs`. Run `npm run cms:push-config`.
- **Fix stale page after CMS publish** → check `/hooks/graph` is receiving requests (look in DXP logs); verify `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` matches the value configured in the Optimizely Graph webhook; confirm the `revalidatePath(path)` call sees the right path; verify Redis is connecting (check `[cache]` log entries).
- **Add a new locale** → extend `routing.locales` in `src/i18n/routing.ts`, add `messages/<locale>.json`, add the language in CMS settings, translate content. No middleware changes needed — next-intl picks up new locales from `routing`.
- **Add CMS preview support to a fresh repo** → ensure `src/app/preview/page.tsx` exists, wraps with `withAppContext`, loads `communicationinjector.js` via `next/script`, renders `<PreviewComponent />`. Confirm `OPTIMIZELY_CMS_URL` is set. Confirm middleware `matcher` excludes `/preview`. Wire up `PreviewError` component for SDK error surfacing.
- **Add an article-listing block** → create a `getXyz(parentPath, locale)` fetcher with `'use cache'` + `cacheLife('max')` + `cacheTag(getArticlesUnderTag(parent, locale))`. Webhook already invalidates ancestor-prefix tags on every publish — no webhook changes needed.
- **Make a section's row/column gap editor-driven** → define a `displayTemplate({ nodeType: 'row', settings: {...} })` (content-types skill). The grid's `StructureContainerProps.displaySettings` exposes the settings; read them in the row/column wrapper.
- **Diagnose a Graph fetch failure shown in preview** → click through the `PreviewError` panel — it surfaces the GraphQL query + variables + error locations and offers copy buttons for GraphiQL paste. Most-common cause: schema desync, fix with `npm run cms:push-config`.
- **Pre-render real pages at build instead of placeholder** → understand the trade-off first (see `references/static-generation.md`). The current placeholder approach is deliberate: DXP build containers have unreliable Graph connectivity. If you switch, accept that build can fail when Graph is unreachable.

## Critical gotchas (quick list)

- `'use cache'` MUST be the first statement of the function body. Comments above are fine.
- `revalidateTag(tag)` without `'max'` as 2nd arg silently fails to invalidate `cacheLife('max')` entries.
- `notFound()` from inside `<Suspense>` returns 200 OK with the not-found body (and CDN caches it for 30 days). Always call `notFound()` outside Suspense and in `generateMetadata`.
- The catch-all `[[...slug]]` (double brackets) matches the locale root too — `/no/` resolves slug to `undefined`, normalised to `[]`. Single-bracket `[...slug]` would not match.
- `next.config.ts` sets `cacheComponents: true` — required for `'use cache'` to work and for the auto-PPR + Suspense story to compose.
- `OPTIMIZELY_GRAPH_GATEWAY` is **a base URL in DXP** (`https://cg.optimizely.com`) but **a full URL locally** (`https://cg.optimizely.com/content/v2`). `getGraphGatewayUrl()` normalises.
- The webhook auth uses `x-api-key` header, not query-param secret. If the env var is missing in DXP, the webhook 401s every request silently from the editor's perspective.
- `initContentTypeRegistry` **replaces** the registry, doesn't merge. Built-in `BlankExperienceContentType` / `BlankSectionContentType` must be explicitly added if used.
- Visual Builder needs `vb:grid` / `vb:row` / `vb:col` marker classes on section/row/column wrappers — not Tailwind, not optional.
- The Redis cache handler falls back to in-memory when `REDIS_URL` is missing — fine locally, but if it falls back in DXP you've lost cross-replica cache sharing and `revalidateTag` won't reach every pod.
- `decodeRichTextEntities` (in `src/lib/rich-text.ts`) is sometimes needed before passing CMS-authored rich text into `<RichText>` — entities can survive the GraphQL transport encoded.

## References

- `references/project-setup.md` — Full `next.config.ts`, `tsconfig.json`, `optimizely.config.mjs`, `package.json`, env file template, Redis cache handler setup, DXP-specific infrastructure
- `references/registration.md` — `src/optimizely.ts` ordering rules, `config()` + `getClient()` rationale, resolver variants, what breaks if a type is unregistered, BlankExperience/BlankSection rules
- `references/data-fetching.md` — `'use cache'` deep dive, `cacheLife` profiles, tag vs path revalidation, error handling, GraphClient method usage, raw `client.request()`, article-listing pattern
- `references/static-generation.md` — Placeholder `generateStaticParams` rationale, runtime cache fills, DXP build connectivity, when to switch to real prerender
- `references/locale-routing.md` — next-intl setup, `routing.ts` / `request.ts` / `navigation.ts`, locale-prefixed Links, preview-route locale bridge
- `references/revalidation-webhook.md` — `/hooks/graph` route, `x-api-key` auth, docId parsing, ancestor article-listing invalidation, CDN purge wiring, programmatic webhook registration
- `references/preview-mode.md` — Preview route setup, `withAppContext` rationale, `PreviewComponent` lifecycle, `communicationinjector.js`, retry pattern for indexing delays, `PreviewError` component
- `references/visual-builder.md` — `OptimizelyComposition` / `OptimizelyGridSection` node contracts, `ComponentWrapper` / `row` / `column` props, `pa()` vs `src()`, `vb:` marker classes, row/column display templates
- `references/image-handling.md` — `remotePatterns` configuration, `damAssets` integration, why no custom loader is needed
- `references/troubleshooting.md` — Symptom-indexed common failures, production hardening checklist, SDK error type taxonomy

## Authoritative sources

- Official SDK source + docs: https://github.com/episerver/content-js-sdk (especially `docs/` `1-installation.md` through `13-cli-commands.md`)
- Companion skill: `optimizely-cms-content-types` (schema authoring, property types, `damAssets`, `RichText` API)
- Optimizely SaaS CMS docs: https://docs.developers.optimizely.com/platform-optimizely
