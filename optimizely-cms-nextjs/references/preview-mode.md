# Preview Mode (`/preview`)

A dedicated route that renders unpublished draft content as-it-would-look, and wires up the CMS's in-context editing iframe.

## The route

```tsx
// app/preview/layout.tsx
export default async function PreviewLayout({
  children,
}: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
```

Minimal — no Header/Footer, no fonts, no locale wrapper. **Preview must render the content only.** Site chrome interferes with the in-context editing feedback loop: the CMS's edit toolbar overlays the iframe, and a header/footer around the previewed block just adds visual noise the editor has to mentally subtract. Keep the preview layout empty.

```tsx
// app/preview/page.tsx
import { GraphClient, type PreviewParams } from '@optimizely/cms-sdk'
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server'
import { PreviewComponent } from '@optimizely/cms-sdk/react/client'
import Script from 'next/script'
import { Suspense } from 'react'

type Props = {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function Page({ searchParams }: Props) {
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
  })

  const response = await client.getPreviewContent(
    (await searchParams) as PreviewParams,
  )

  if (!response) {
    return <div>No content found for the given parameters.</div>
  }

  return (
    <>
      <Script
        src={`${process.env.OPTIMIZELY_CMS_HOST}/util/javascript/communicationinjector.js`}
      />
      <PreviewComponent />
      <Suspense fallback={<div>Loading…</div>}>
        <OptimizelyComponent content={response} />
      </Suspense>
    </>
  )
}
```

## The four pieces

### 1. `client.getPreviewContent(searchParams)`
- Accepts a `PreviewParams` object built from URL search params
- Returns the draft content with preview tokens baked in
- Under the hood it also calls `setContext()` so downstream `getPreviewUtils` / `src()` calls know they're in preview mode

`PreviewParams` shape:
```ts
{
  preview_token: string;   // signed short-lived token
  key:           string;   // content GUID
  ctx:           'edit' | 'preview' | 'default';
  ver:           string;   // version to fetch
  loc:           string;   // locale
}
```

The CMS supplies all five via query string when it opens the preview iframe.

### 2. `communicationinjector.js` script
```tsx
<Script src={`${process.env.OPTIMIZELY_CMS_HOST}/util/javascript/communicationinjector.js`} />
```

This is a script hosted by your CMS instance (NOT bundled with your app — loaded fresh from the CMS on every preview). It enables the Optimizely editing UI to talk to your page across the iframe — click-to-edit, inline field updates, live refresh on save.

Without it, preview is **read-only**: the page renders draft content correctly, but the editor toolbar can't connect to it. No edit highlighting, no click-to-edit, no live updates on save.

**If `OPTIMIZELY_CMS_HOST` is wrong or unset, preview silently degrades** the same way. There's no error, just no interactivity. Validate the env var in production smoke tests.

### 3. `<PreviewComponent />` (client)
Imported from `@optimizely/cms-sdk/react/client`. A thin `'use client'` component that:
- Listens for `optimizely:cms:contentSaved` DOM events from the injector script
- Reloads the preview with fresh tokens on save

Always render it once per preview page, near the injector script. It has no props and no visible UI.

### 4. `<OptimizelyComponent content={response} />`
Same component you use on public pages. The SDK detects preview context (set by `getPreviewContent`) and injects `data-epi-*` attributes automatically via any `getPreviewUtils.pa()` calls in your component tree.

## Why the preview route is not locale-prefixed

The middleware's `shouldExclude` includes `/preview` so the path is never rewritten to `/en/preview`. The CMS's preview iframe requests exactly `/preview?<params>`, and any redirect would break the flow (the iframe loses search params or the CSP's `frame-ancestors` check applies to the wrong origin).

## Required configuration

- **`OPTIMIZELY_CMS_HOST`** — without this, the injector script URL is malformed.
- **CSP `frame-ancestors 'self' *.optimizely.com`** — set in `next.config.ts`. Without this, browsers block the iframe embed.
- **Middleware exclusion** — `/preview` must be in `shouldExclude`.

## Suspense wrapper — why

`PreviewComponent` is a client component but `OptimizelyComponent` is an async server component. In Next.js 16, wrapping the async server component in `<Suspense>` is required when it lives next to a client component in the same render tree, otherwise the client component's JS bundle won't hydrate until the server component finishes fetching.

## Distinguishing preview from public fetches

In preview, the SDK adds a `__context` field to each content node:

```ts
content.__context?.edit          // true in edit mode
content.__context?.preview_token // the token; use via getPreviewUtils.src() for image URLs
```

If you need to branch rendering (e.g. show edit hints only in preview):
```ts
const isEditing = content.__context?.edit ?? false
```

Most of the time you don't need to check — the SDK's `pa()` helper returns `{}` in published mode, so your code works identically.

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Preview page renders but CMS toolbar never connects | `OPTIMIZELY_CMS_HOST` wrong/unset | Set to `https://<instance>.cms.optimizely.com` |
| Preview iframe shows blank / console CSP error | Missing `frame-ancestors` in CSP | Add the CSP header in `next.config.ts` |
| Preview URL returns a redirect before loading | Middleware not excluding `/preview` | Add `/preview` to `shouldExclude` in `proxy.ts` |
| Clicking edit doesn't switch to edit mode | Missing `<PreviewComponent />` in the route | Add it |
| Content appears stale even after editor saves | Missing `<PreviewComponent />` or injector script loading too late | Keep them both at the top of the JSX tree |
| `TypeError: searchParams.then is not a function` | Next.js 16 makes `searchParams` a Promise — must `await` | `await searchParams` |

## Don't unify preview with public rendering

Tempting to do:
```ts
// DON'T
async function getContent(locale, slug, preview) {
  return preview
    ? client.getPreviewContent(...)
    : client.getContentByPath(...)
}
```

Keep them separate. `getPreviewContent` requires full token context that public pages don't have. Mixing them leads to:
- Token leaks into caches
- `'use cache'` keying by preview params → unbounded cache growth
- Preview-only behaviour accidentally triggered in published rendering

Two routes, two fetch paths, no shared wrapper.
