# Revalidation Webhook (`/api/revalidate`)

Receives a POST from Optimizely CMS when content is published. Authenticates, resolves the published item's URL, and invalidates the right cache entry.

## Full route

```ts
// app/api/revalidate/route.ts
import { GraphClient } from '@optimizely/cms-sdk'
import { revalidatePath, revalidateTag } from 'next/cache'
import { type NextRequest, NextResponse } from 'next/server'
import { CACHE_KEYS, getCacheTag } from '@/lib/cache/cache-keys'

const OPTIMIZELY_REVALIDATE_SECRET = process.env.OPTIMIZELY_REVALIDATE_SECRET

export async function POST(request: NextRequest) {
  try {
    validateWebhookSecret(request)
    const docId = await extractDocId(request)

    if (!docId || !docId.includes('Published')) {
      return NextResponse.json({ message: 'No action taken' })
    }

    const [guid, locale] = docId.split('_')
    const formattedGuid = guid.replaceAll('-', '')

    const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
      graphUrl: process.env.OPTIMIZELY_GRAPH_URL,
    })

    const contentData = await client.request(GET_CONTENT_BY_GUID_QUERY, {
      guid: formattedGuid,
      locale: [locale],
    } as any)

    const content = contentData?._Content?.item
    const urlType = content?._metadata?.url?.type

    // Hierarchical: Start Page is NOT '/' — it has a real path like '/start-page'.
    // Strip OPTIMIZELY_START_PAGE_URL to normalize.
    const url =
      urlType === 'SIMPLE'
        ? content?._metadata?.url?.default
        : content?._metadata?.url?.hierarchical?.replace(
            process.env.OPTIMIZELY_START_PAGE_URL ?? '',
            '',
          )

    if (!url) {
      return NextResponse.json({ message: 'Page Not Found' }, { status: 400 })
    }

    const urlWithLocale = normalizeUrl(url, locale)
    await handleRevalidation(urlWithLocale, locale)

    return NextResponse.json({ revalidated: true, now: Date.now() })
  } catch (error) {
    return handleError(error)
  }
}

const GET_CONTENT_BY_GUID_QUERY = `
  query GetContentByGuid($guid: String, $locale: [Locales]) {
    _Content(locale: $locale, where: { _metadata: { key: { eq: $guid } } }) {
      item {
        _metadata {
          displayName
          url { hierarchical default type }
        }
      }
    }
  }
`

function validateWebhookSecret(request: NextRequest) {
  const webhookSecret = request.nextUrl.searchParams.get('cg_webhook_secret')
  if (webhookSecret !== OPTIMIZELY_REVALIDATE_SECRET) {
    throw new Error('Invalid credentials')
  }
}

async function extractDocId(request: NextRequest): Promise<string> {
  const requestJson = await request.json()
  return requestJson?.data?.docId || ''
}

function normalizeUrl(url: string, locale: string): string {
  let normalizedUrl = url.startsWith('/') ? url : `/${url}`
  if (normalizedUrl.endsWith('/')) normalizedUrl = normalizedUrl.slice(0, -1)
  return normalizedUrl.startsWith(`/${locale}`)
    ? normalizedUrl
    : `/${locale}${normalizedUrl}`
}

async function handleRevalidation(urlWithLocale: string, locale: string) {
  if (urlWithLocale.includes('footer')) {
    const footerTag = getCacheTag(CACHE_KEYS.FOOTER, locale)
    revalidateTag(footerTag, 'max')
  } else if (urlWithLocale.includes('header')) {
    const headerTag = getCacheTag(CACHE_KEYS.HEADER, locale)
    revalidateTag(headerTag, 'max')
  } else {
    revalidatePath(urlWithLocale)
  }
}

function handleError(error: unknown) {
  console.error('Error processing webhook:', error)
  if (error instanceof Error) {
    if (error.message === 'Invalid credentials') {
      return NextResponse.json({ message: 'Invalid credentials' }, { status: 401 })
    }
    return NextResponse.json({ message: error.message }, { status: 500 })
  }
  return NextResponse.json({ message: 'Internal Server Error' }, { status: 500 })
}
```

## CMS webhook configuration

Webhooks are managed at `https://cg.optimizely.com/api/webhooks` (see https://docs.developers.optimizely.com/platform-optimizely/docs/manage-webhooks).

Required configuration for the starter's pattern:

- **Method:** POST
- **URL:** `https://<your-domain>/api/revalidate?cg_webhook_secret=<OPTIMIZELY_REVALIDATE_SECRET>`
- **Content-Type:** `application/json`
- **Topics (must include BOTH):**
  - `doc.updated` — single-document publish events
  - `bulk.completed` — batch publish operations
- **Filter:** `"filters": { "status": { "eq": "Published" } }`

### Why both topics

Omitting `bulk.completed` is a common silent-failure: an editor batch-publishing ten articles triggers one bulk event, not ten `doc.updated` events. Without the bulk subscription, every batch publish leaves pages stale.

### Why the status filter

Without `status: { eq: "Published" }`, the webhook fires on draft saves too — every keystroke in the editor hits your endpoint. This burns Optimizely's webhook quota and hammers your cache for no user benefit. Always filter to Published.

### Why shared secret

The secret is a query parameter, **not a header**. Without it, `/api/revalidate` is a DoS / cache-thrash vector: any caller could force arbitrary path revalidations and blow out your caches. Always validate the secret — and see the Hardening section below for the next tier of protection.

## Payload shape

```json
{
  "type":    { "subject": "doc", "action": "completed" },
  "data":    { "docId": "abc12345-6789-4def-0000-111122223333_en_Published" }
}
```

The `docId` is `<UUID-with-dashes>_<locale>_Published`. The route extracts guid + locale via `split('_')`, then strips dashes (`replaceAll('-', '')`) before querying Graph, because the Graph `_metadata.key` field stores the UUID without dashes.

The `Published` suffix is the trigger — without it, we return `"No action taken"` (200) to prevent retries. Unpublished saves / other variation events don't warrant revalidation.

## URL resolution — SIMPLE vs hierarchical

Optimizely Content Graph exposes two URL views:

| `url.type` | Meaning | What to use |
|---|---|---|
| `SIMPLE` | Flat URL, CMS stores exactly what editors typed | `url.default` |
| `HIERARCHICAL` | Tree-derived URL; includes the Start Page prefix | `url.hierarchical` with `OPTIMIZELY_START_PAGE_URL` stripped |

Example:
- A page titled "About" under the Start Page `/start-page`:
  - `url.hierarchical` = `/start-page/about/`
  - `url.default` = `/about/` (if editor set it)
  - With hierarchical routing → strip `/start-page` → `/about/`

The hierarchical strip ONLY applies when `url.type !== 'SIMPLE'`. Don't blanket-strip the prefix.

## URL normalization

After resolving the CMS-side URL:
1. Prepend `/` if missing
2. Strip trailing `/`
3. Prepend `/${locale}` if the path doesn't already start with the locale

So `/about/` + locale `en` becomes `/en/about`. That's what `revalidatePath` expects — it must match what `[...slug]/page.tsx` renders under.

## Tag vs path revalidation — the routing rule

```
urlWithLocale contains 'footer' → revalidateTag(getCacheTag(CACHE_KEYS.FOOTER, locale), 'max')
urlWithLocale contains 'header' → revalidateTag(getCacheTag(CACHE_KEYS.HEADER, locale), 'max')
otherwise                       → revalidatePath(urlWithLocale)
```

Why the split: Header and Footer are rendered by the locale layout on *every* page. A single `revalidatePath` couldn't reach them all — there's no one URL to target. Tags do: one `revalidateTag('optimizely-header-en', 'max')` call invalidates the Header cache entry for every page in `/en/*`.

For a regular CMS page at `/en/about`, the content shows up in exactly one route, so `revalidatePath('/en/about')` is sufficient.

**Always pass `'max'` as the second arg to `revalidateTag`** when the cached function used `cacheLife('max')`. Otherwise Next.js treats the tag as short-lived and silently no-ops on long-lived entries.

### Header/Footer-as-CMS-page as a reusable template

The "model shared config as a CMS page with its own cache tag" pattern isn't just for navigation. Apply it to anything that's (a) read on every page and (b) edited occasionally:

- **SiteSettings** — per-locale Algolia keys, feature flags, analytics IDs exposed to the client.
- **PromoBar** — site-wide announcement banner.
- **GlobalFooter** — already in the starter.
- **Legal text** — cookie banner copy, disclaimer text.

Template:
1. Define a `_page` content type (e.g. `SiteSettingsPage`) at a fixed CMS path (e.g. `/{locale}/site-settings/`).
2. Fetch it in a server component with `'use cache'` + `cacheTag(getCacheTag(CACHE_KEYS.SITE_SETTINGS, locale))`.
3. In the webhook's URL routing, add a branch: `urlWithLocale.includes('site-settings') → revalidateTag(...)`.

One editor edit → one tag invalidation → every rendered page sees the update on next request. Avoids path-based revalidation fan-out.

## Hardening — production considerations

The starter's `/api/revalidate` is secret-gated but otherwise public. For production, consider:

- **Rate limiting.** A leaked secret or a misconfigured CMS could flood the endpoint. Upstash Ratelimit + Redis is the canonical Next.js pattern: wrap the handler in a sliding-window limiter keyed by IP.
- **IP allowlist.** Optimizely publishes the IP ranges its webhooks originate from. Narrow the endpoint to those ranges at the CDN/WAF layer.
- **Structured logging.** Replace `console.log/error` with Pino or Winston (or your platform's structured logger). Log the `docId`, `urlType`, resolved `urlWithLocale`, and revalidation outcome for every request — otherwise silent failures are invisible.
- **Error tracking.** Wire Sentry (or equivalent) around the handler. The try/catch currently swallows details into a JSON response body; errors need to land in an operational channel.
- **Tests.** The webhook's docId parser + URL resolver has enough branches (SIMPLE vs hierarchical, header/footer vs page, missing URL, missing content) to warrant unit tests. No tests are in the starter — this is called out explicitly by the course as a production gap.

None of this is required for functional parity with the starter, but all of it is standard for a prod-grade CMS integration.

## Error contract

| Situation | Response |
|---|---|
| `cg_webhook_secret` missing or wrong | 401 `{ "message": "Invalid credentials" }` |
| `docId` missing or doesn't include `Published` | 200 `{ "message": "No action taken" }` |
| Content not found in Graph | 400 `{ "message": "Page Not Found" }` |
| Any other error | 500 `{ "message": <error.message> }` |
| Success | 200 `{ "revalidated": true, "now": <timestamp> }` |

Optimizely's webhook retry policy typically treats non-200 responses as retryable. Returning 200 with `"No action taken"` is intentional for "don't retry, nothing to do" cases.

## Testing locally

Use `curl` to simulate:

```sh
curl -X POST 'http://localhost:3000/api/revalidate?cg_webhook_secret=<your-secret>' \
  -H 'Content-Type: application/json' \
  -d '{"data":{"docId":"abc12345-6789-4def-0000-111122223333_en_Published"}}'
```

For a real test, the guid must match a published item in your Graph instance. Otherwise you'll get the "Page Not Found" branch — which confirms the auth+parse logic works but doesn't exercise the revalidation.

## Debugging "content doesn't update after publish"

1. **Secret mismatch** — check the CMS webhook config includes the right `cg_webhook_secret`. Mismatch returns 401, webhook retries eventually give up.
2. **`revalidateTag` without `'max'`** — classic silent no-op. Verify the call uses `revalidateTag(tag, 'max')`.
3. **`OPTIMIZELY_START_PAGE_URL` wrong or unset** — for hierarchical routing, wrong prefix means wrong path passed to `revalidatePath`. Add `console.log(urlWithLocale)` to verify.
4. **Cached downstream** — if you deploy behind a CDN (Cloudflare, Vercel Edge), the CDN may be caching the HTML separately from Next.js. Add a `Cache-Control: no-cache` on the page response or configure CDN to respect Next.js cache tags.
5. **Middleware matcher** — confirm `/api/revalidate` is excluded. A misconfigured matcher will rewrite the POST to `/en/api/revalidate` and 404.
6. **Content not `Published`** — saving-as-draft doesn't trigger a publish webhook. Confirm the editor actually clicked Publish.
