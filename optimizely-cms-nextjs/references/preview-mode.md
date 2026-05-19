# Preview Mode (`/preview`)

A dedicated route that renders unpublished draft content as-it-would-look and wires up the CMS's in-context editing iframe. Wrapped in `withAppContext` so SDK helpers (`getContextData`, `RichText`, `src()`) see the preview token.

## The route

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

  // Bridge the CMS-supplied `loc` searchParam into next-intl so any
  // useTranslations() call inside rendered components resolves.
  const locParam = typeof params.loc === 'string' ? params.loc : undefined;
  const locale = hasLocale(routing.locales, locParam) ? locParam : routing.defaultLocale;
  setRequestLocale(locale);
  const messages = (await import(`../../../messages/${locale}.json`)).default;

  const client = getClient();
  let response;
  let error: unknown = null;

  // Editor publishes can briefly precede Graph indexing — retry with backoff
  // when "No content found for key" surfaces.
  for (let attempt = 0; attempt <= 3; attempt++) {
    try {
      error = null;
      response = await client.getPreviewContent(params as PreviewParams);
      break;
    } catch (err: unknown) {
      error = err;
      const isNotYetIndexed =
        err instanceof Error && err.message.includes('No content found for key');
      if (isNotYetIndexed && attempt < 3) {
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

// withAppContext: initialises request-scoped context. getPreviewContent()
// then populates it with preview_token, key, locale, version, mode.
// Components down the tree read via getContextData(); RichText automatically
// uses preview_token to append it to image URLs.
export default withAppContext(Page);
```

## The five pieces

### 1. `withAppContext(Page)` HOC

Required wrapper. Initialises request-scoped context storage. Without it:
- `getPreviewContent` can't populate context
- `getContextData('preview_token' | …)` returns nothing
- `RichText` doesn't append preview tokens to image URLs
- `getPreviewUtils(content).src(image)` doesn't append the token

Apply as `export default withAppContext(Page)` — not as a wrapper component inside the JSX. The HOC needs to wrap the route's default export so Next.js calls it at request entry.

### 2. `getPreviewContent(searchParams)`

Accepts `PreviewParams`:
```ts
{
  preview_token: string;   // signed short-lived token
  key: string;             // content GUID
  ctx: 'edit' | 'preview' | 'default';
  ver: string;             // version to fetch
  loc: string;             // locale
}
```

Returns the draft content with the preview context baked in. Also calls `setContext()` internally so downstream `getPreviewUtils.src()` and `RichText` know they're in preview.

The CMS supplies all five params via query string when it opens the preview iframe — the searchParams shape matches `PreviewParams` directly.

### 3. `communicationinjector.js` script

```tsx
<Script
  src={`${process.env.OPTIMIZELY_CMS_URL}/util/javascript/communicationinjector.js`}
  strategy="beforeInteractive"
  id="optimizely-communication-injector"
/>
```

This script is hosted by the CMS instance (NOT bundled with your app — fetched fresh from the CMS on every preview). It enables the Optimizely editing UI to talk to your page across the iframe: click-to-edit, inline field updates, live refresh on save.

**`strategy="beforeInteractive"`** is required. The other strategies run after first paint and miss the early events the editor emits.

**Without it, preview is read-only**: the page renders draft content correctly, but the editor toolbar can't connect. No edit highlighting, no click-to-edit, no live updates on save.

**If `OPTIMIZELY_CMS_URL` is wrong or unset, preview silently degrades the same way.** The `<Script src>` produces `https://undefined/util/javascript/communicationinjector.js`, the browser logs a network error, and the editor stays disconnected. Validate the env var in production smoke tests.

### 4. `<PreviewComponent />` (client)

Imported from `@optimizely/cms-sdk/react/client`. A thin `'use client'` component that:
- Listens for `optimizely:cms:contentSaved` DOM events from the injector
- Reloads the preview with fresh tokens on save

Render it once per preview page, near the injector script. No props, no visible UI.

### 5. `<OptimizelyComponent content={response} />`

Same component used on public pages. The SDK detects preview context (set by `getPreviewContent` via `withAppContext`-initialised storage) and the `pa()` helper from `getPreviewUtils` returns real `data-epi-*` attributes (rather than the no-op `{}` it returns in published mode).

## The locale bridge

`/preview` is excluded from the next-intl middleware. The CMS supplies `loc` as a searchParam, but `next-intl` won't pick that up automatically. The PreviewBody manually:

1. Reads `params.loc`
2. Validates against `routing.locales`
3. Calls `setRequestLocale(locale)` so server-component translations work
4. Loads the messages JSON for the locale
5. Wraps the body in `<NextIntlClientProvider locale={locale} messages={messages}>` so client-component translations work

This explicit setup (instead of relying on `getRequestConfig`) is the cost of `/preview` living outside the `[locale]` segment.

## Retry pattern — indexing delays

When an editor publishes, the CMS sometimes opens the preview iframe a fraction of a second before Optimizely Graph has finished indexing the new version. `getPreviewContent` throws "No content found for key" until the index catches up.

The handler retries up to 3 times with 200ms backoff:

```ts
for (let attempt = 0; attempt <= 3; attempt++) {
  try {
    response = await client.getPreviewContent(params as PreviewParams);
    break;
  } catch (err) {
    const isNotYetIndexed =
      err instanceof Error && err.message.includes('No content found for key');
    if (isNotYetIndexed && attempt < 3) {
      await new Promise((r) => setTimeout(r, 200));
      continue;
    }
    break;
  }
}
```

Only the indexing-delay message triggers retry; other errors (auth, network, GraphQL) propagate to `PreviewError` immediately.

## `PreviewError` — structured SDK error surfacing

The repo includes `src/components/layout/PreviewError.tsx` that detects SDK error types via the `name` property and renders structured diagnostics:

- **Error type badge** — `GraphContentResponseError`, `GraphMissingContentTypeError`, `GraphHttpResponseError`, etc.
- **GraphQL errors** — message, location (line/column), extensions
- **Query + variables** — copy-to-clipboard for GraphiQL paste
- **Troubleshooting tips** — context-aware suggestions ("run `npm run cms:push-config`" for missing-type errors, etc.)
- **Full error details** — collapsed `<details>` with the raw error payload

This turns "preview is broken" from a black box into a debuggable artifact. When wiring preview in a new project, port this component too — it pays back the first time a query fails in front of an editor.

SDK error hierarchy used:
```
OptimizelyGraphError
  ├─ GraphMissingContentTypeError  (contentType: string)
  └─ GraphResponseError            (request: { query, variables })
      └─ GraphHttpResponseError    (status: number)
          └─ GraphContentResponseError (errors: { message, locations }[])
```

Type guards key off `err.name` (set by each SDK error class).

## Why the preview route is not locale-prefixed

The middleware's matcher excludes `/preview`. The CMS iframe requests exactly `/preview?...params`, and any locale redirect would:
- Strip the searchParams (depending on Next.js version)
- Apply CSP `frame-ancestors` to the wrong origin
- Break the editor's iframe<->page communication

Keep `/preview` outside the `[locale]` segment and outside the middleware matcher.

## Required environment variables

| Variable | Purpose |
|---|---|
| `OPTIMIZELY_CMS_URL` | Communication injector script source. Without it, preview shows draft content but the editor toolbar doesn't connect. |
| `OPTIMIZELY_GRAPH_SINGLE_KEY` | Standard Graph auth — same key the catch-all uses. |
| `OPTIMIZELY_GRAPH_GATEWAY` | Standard Graph gateway — same as catch-all. |

If `next.config.ts` sets `headers()` with CSP that restricts `frame-ancestors`, ensure `*.optimizely.com` is allowed:

```ts
async headers() {
  return [{
    source: '/(.*)',
    headers: [
      { key: 'Content-Security-Policy', value: "frame-ancestors 'self' *.optimizely.com" },
    ],
  }];
}
```

This repo's `next.config.ts` doesn't set CSP — DXP's edge layer handles it. Confirm before deploying outside DXP.

## CMS-side preview configuration

In the CMS instance:
1. **Settings → Hostnames** → add the deployment URL (`https://yourdomain.com`).
2. **Live Preview** tab → enable "Use Preview Tokens", set Preview URL format to `https://yourdomain.com/preview`.
3. Configure separate preview URLs per environment (local/staging/prod) if needed.

## Reading preview context in components

```ts
import { getContextData } from '@optimizely/cms-sdk/react/server';

export function PreviewBanner() {
  const preview_token = getContextData('preview_token');
  const ctx = getContextData('mode');   // 'edit' | 'preview' | 'default'

  if (!preview_token) return null;
  return <div className="preview-banner">Preview mode ({ctx})</div>;
}
```

Available context fields:
- `preview_token` — set in preview, empty in published rendering
- `locale` — the CMS-supplied `loc` (separately bridged to next-intl above)
- `key` — content GUID
- `version` — content version
- `mode` — `'default'` | `'edit'` | `'preview'`

For locale-aware logic, prefer next-intl's `useLocale()` / `getLocale()` — the SDK's locale context is a copy of the same value.

## Distinguishing preview from public rendering in components

Most of the time you don't need to. `pa()` from `getPreviewUtils` returns `{}` in published mode, so spreading `{...pa('title')}` is a no-op outside preview. `src()` returns the URL unchanged in published mode. `RichText` reads preview tokens via context but is a no-op without them.

If you need explicit branching:
```ts
const isEditing = !!getContextData('preview_token');
```

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Preview page renders draft content but editor toolbar doesn't connect | `OPTIMIZELY_CMS_URL` wrong/unset | Set to `https://<instance>.cms.optimizely.com` (no trailing slash) |
| Preview iframe shows blank / "refused to connect" | CSP `frame-ancestors` blocks `*.optimizely.com` | Allow `*.optimizely.com` in CSP, or rely on DXP's edge headers |
| Preview URL redirects before loading | Middleware matcher includes `/preview` | Confirm `preview` is in the exclusion list (it is, in this repo) |
| Clicking edit doesn't switch to edit mode | Missing `<PreviewComponent />` in the route | Add it |
| Content stale on save | `<PreviewComponent />` or injector script loading too late | Use `strategy="beforeInteractive"` for the script; render both near the top of the JSX |
| Preview banner shows wrong locale | Missing locale bridge in PreviewBody | Read `params.loc`, validate, `setRequestLocale`, wrap in `<NextIntlClientProvider>` |
| Draft images don't load | Component bypassing `getPreviewUtils.src()` | Use `src(content.image)` not `content.image.url.default` |
| `TypeError: searchParams.then is not a function` | Next.js 16: `searchParams` is a Promise | `await searchParams` |
| "No content found for key" persists past retry | The published version genuinely isn't indexed yet | Wait a few seconds and refresh; if persistent, check Graph webhook config |

## Don't unify preview with public rendering

Tempting:

```ts
// DON'T
async function getContent(locale, slug, preview) {
  return preview
    ? client.getPreviewContent(...)
    : client.getContentByPath(...);
}
```

Keep them separate. `getPreviewContent` requires full token context that public pages don't have. Mixing them leads to:
- Token leaks into caches (`'use cache'` keyed by preview params → unbounded cache growth)
- Preview-only behaviour accidentally triggered in published rendering
- The `withAppContext` requirement spreads to public routes for no benefit

Two routes, two fetch paths, no shared wrapper.
