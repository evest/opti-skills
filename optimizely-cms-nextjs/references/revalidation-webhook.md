# Revalidation Webhook (`/hooks/graph`)

Receives a POST from Optimizely Graph when content is published. Authenticates via `x-api-key` header, resolves the docId to a URL, invalidates the right cache entries, and fires a CDN purge for the affected URL.

## Full route

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

/** Resolve a docId to a URL path and revalidate. Returns the resolved
 *  path on success, "" if the doc can't be resolved.
 *
 *  docId format: `{UUID}_{language}_Published` */
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

  // Invalidate every ancestor article-listing cache. revalidateTag on an
  // unwritten tag is a no-op, so over-invalidating costs nothing.
  const segments = path.split('/').filter(Boolean);
  for (let i = 1; i < segments.length; i++) {
    const parent = `/${segments.slice(0, i).join('/')}/`;
    revalidateTag(getArticlesUnderTag(parent, locale), 'max');
  }

  // Sitemap is tagged with PATHS; cacheLife('hours') so revalidate accordingly.
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

## Authentication: `x-api-key` header (not query param)

The webhook reads `x-api-key` from the request headers and compares against `OPTIMIZELY_GRAPH_CALLBACK_APIKEY`. **If the env var is missing in production, the webhook 401s every request silently** — from the editor's perspective, publishing "doesn't update the site". Always verify the env var is present in DXP before debugging anything else.

Why header and not query param:
- Headers don't end up in access logs by default — less leak surface
- Easier to rotate (CMS Graph webhook config stores the secret server-side)
- Matches Optimizely Graph's documented webhook auth pattern

## CMS webhook configuration

Webhooks are managed at `https://cg.optimizely.com/api/webhooks` (see <https://docs.developers.optimizely.com/platform-optimizely/docs/manage-webhooks>).

Required configuration:
- **Method**: POST
- **URL**: `https://<your-domain>/hooks/graph`
- **Headers**: `x-api-key: <OPTIMIZELY_GRAPH_CALLBACK_APIKEY>`
- **Content-Type**: `application/json`
- **Topics**: subscribe to `doc.updated`. The handler also responds to `doc.expired`.
- **Filter**: `"filters": { "status": { "eq": "Published" } }` so draft saves don't trigger.

If publishes are heavy, also subscribe to `bulk.completed` and add a branch handling the bulk payload shape — this project's handler currently only routes single-doc events, which is sufficient for the typical editor workflow but misses big bulk operations.

### Why the status filter

Without `status: { eq: "Published" }`, the webhook fires on draft saves — every keystroke in the editor potentially hits your endpoint, burning Optimizely's webhook quota and thrashing the cache for no benefit. Always filter to `Published`.

## Payload shape

```json
{
  "type":    { "subject": "doc", "action": "updated" },
  "data":    { "docId": "abc12345-6789-4def-0000-111122223333_en_Published" }
}
```

`docId` format: `<UUID-with-dashes>_<locale>_Published`.

The handler:
1. Splits on `_` → `[rawId, locale]`
2. Strips dashes from `rawId` → `id` (Graph stores keys without dashes in `_metadata.key`)
3. Queries Graph for `_Content(ids: [id], locale: [locale])` → reads `_metadata.url.default`
4. Strips trailing slash → calls `revalidatePath(path)`

## URL resolution

This repo uses `_metadata.url.default` exclusively — no SIMPLE-vs-hierarchical branching. The default URL is what the editor sees, what `getContentByPath` queries, and what the catch-all renders under. One source of truth.

If your CMS instance uses hierarchical routing where the Start Page has a real path that needs stripping (e.g. `/start-page/about`), you'd need:

```ts
const url = response?._Content?.item?._metadata?.url?.default
  ?? response?._Content?.item?._metadata?.url?.hierarchical?.replace(
       process.env.OPTIMIZELY_START_PAGE_URL ?? '',
       '',
     );
```

This project doesn't use hierarchical, so the simpler version above suffices.

## Tag invalidation — what gets invalidated and why

Three things on every successful publish:

1. **`revalidatePath(path)`** — the page itself. The Redis cache entry tagged with the implicit `_N_T_<path>` tag is deleted.

2. **`revalidateTag(getArticlesUnderTag(parent, locale), 'max')` for every ancestor prefix** — invalidates any article-listing block that's filtering by ancestor path. For `/no/blog/post-1`:
   - `parent = '/no/'`  → invalidates `opti-articles-under:/no/:no`
   - `parent = '/no/blog/'` → invalidates `opti-articles-under:/no/blog/:no`

   `revalidateTag` on an unwritten tag is a cheap no-op, so over-invalidating costs nothing. The 'max' second arg matches the listing block's `cacheLife('max')` profile.

3. **`revalidateTag(CACHE_KEYS.PATHS, 'hours')`** — the sitemap. `cacheLife('hours')` so the 'hours' second arg matches.

The `'max'` / `'hours'` second argument is essential. Without it, `revalidateTag` silently no-ops against entries cached at a longer-lived profile.

## CDN cache purge

After `revalidatePath` succeeds, the handler fires a CDN purge for the affected URL:

```ts
const hostname = process.env.OPTIMIZELY_SITE_HOSTNAME?.replace(/^https?:\/\//, '');
if (hostname) {
  purgeCdnCache([`https://${hostname}${path}`]).catch((err) =>
    console.error('[hooks] CDN cache purge failed:', err.message),
  );
}
```

`purgeCdnCache` lives in `src/lib/cdn-cache.ts`. It calls the Cloud Platform Services edge-cache API with a managed-identity Bearer token:

```ts
// src/lib/cdn-cache.ts (abbreviated)
import { ManagedIdentityCredential } from '@azure/identity';

const API_URL = (process.env.OPTIMIZELY_CLOUDPLATFORM_API_URL ?? '').replace(/\/+$/, '');
const RESOURCE_ID = process.env.OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID;

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 5 * 60 * 1000) {
    return cachedToken.token;
  }
  const credential = process.env.AZURE_CLIENT_ID
    ? new ManagedIdentityCredential({ clientId: process.env.AZURE_CLIENT_ID })
    : new ManagedIdentityCredential();
  const response = await credential.getToken(`${RESOURCE_ID}/.default`);
  cachedToken = { token: response.token, expiresAt: response.expiresOnTimestamp };
  return response.token;
}

export async function purgeCdnCache(urls?: string[]): Promise<void> {
  if (!API_URL || !RESOURCE_ID) {
    console.warn('CDN cache purge skipped: API URL or resource ID not configured');
    return;
  }
  // ... POST to ${API_URL}/v1/edge-cache/purge with Bearer token ...
}
```

The API is **asynchronous** — returns 202 Accepted with an `operationId` and processes the purge in the background. Treat it as fire-and-forget; the `.catch` in the webhook logs failures but doesn't retry.

When `OPTIMIZELY_CLOUDPLATFORM_API_URL` / `OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID` are missing (typical for local dev), `purgeCdnCache` no-ops with a warning. That's the right behaviour for local — there's no CDN in front of the dev server.

## Error contract

The handler always returns 200 (with `received: true` or an `error` field) so Optimizely doesn't retry on transient downstream failures. Optimizely's retry policy typically treats non-200 as retryable; returning 200 with an embedded error signals "I got it, don't retry, problem is on my side".

| Situation | Response |
|---|---|
| `x-api-key` missing or wrong | 401 `{ error: 'Unauthorized' }` |
| docId resolves to no content | 200 `{ received: true }` (path empty, no revalidation) |
| Graph query fails | 200 `{ received: true }` (error logged, doesn't throw out of POST) |
| Successful revalidation | 200 `{ received: true }` |

The choice to suppress errors into 200 + log trades off retry hygiene for not flooding the editor with "publish failed" toasts. If you need stricter semantics, return 5xx for transient errors and accept the retry cost.

## Testing locally

Curl simulation:

```sh
curl -X POST 'http://localhost:3000/hooks/graph' \
  -H 'x-api-key: <your-secret>' \
  -H 'Content-Type: application/json' \
  -d '{"type":{"subject":"doc","action":"updated"},"data":{"docId":"<guid-with-dashes>_no_Published"}}'
```

For a real test, the guid must match a published item in your Graph instance. Otherwise the `_Content` query returns nothing, `path` is empty, and the response is `{ received: true }` with no revalidation — which confirms auth + parse works but doesn't exercise `revalidatePath`.

## Adding a new tagged cache to the invalidation flow

Pattern:
1. Define the tag composer in `src/lib/cache/cache-keys.ts`:
   ```ts
   export const CACHE_KEYS = {
     // ... existing ...
     NEW_THING: 'opti-new-thing',
   } as const;
   ```
2. Use it in the fetcher:
   ```ts
   'use cache';
   cacheLife('max');
   cacheTag(CACHE_KEYS.NEW_THING);
   ```
3. Add a branch in the webhook:
   ```ts
   revalidateTag(CACHE_KEYS.NEW_THING, 'max');
   ```

If the cache is keyed (e.g. per locale or per parent path), follow the `getArticlesUnderTag` pattern: a composer in `cache-keys.ts` that the webhook can call with the relevant inputs from the URL/payload.

## Production hardening

The handler is `x-api-key`-gated but otherwise public. For production at scale, consider:

- **Rate limiting.** Wrap the handler in a sliding-window limiter (e.g. Upstash Ratelimit) keyed by IP.
- **IP allowlist.** Optimizely publishes the IP ranges its webhooks originate from. Narrow at the WAF/CDN layer.
- **Structured logging.** Replace `console.error` with a structured logger (Pino, Winston) — emit docId, resolved path, revalidation outcome.
- **Error tracking.** Wire Sentry around the handler. The `.catch` on `purgeCdnCache` currently logs and forgets; production needs an alarm path.
- **Unit tests** for the docId parser + revalidation routing. Enough branches (header/footer routing if you add it, ancestor invalidation, missing URL, etc.) to warrant coverage.

None of this is required for functional parity — all of it is standard for prod-grade CMS integration.

## Debugging "content doesn't update after publish"

1. **Webhook not reaching the app** — check DXP access logs for `POST /hooks/graph`. If nothing, the CMS webhook config is wrong (URL, secret).
2. **401 in logs** — `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` mismatch between DXP env and CMS webhook config.
3. **200 received but content stale** — check the response in DXP logs. If `path` resolved correctly, `revalidatePath` ran but the Redis handler may not be wired (see `references/static-generation.md` "the cache isn't sharing across replicas").
4. **`revalidateTag` missing `'max'`** — silent no-op. Verify the call uses `revalidateTag(tag, 'max')`.
5. **CDN cache not purged** — check `OPTIMIZELY_SITE_HOSTNAME`, `OPTIMIZELY_CLOUDPLATFORM_API_URL`, `OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID` are present and the managed identity has `edge-cache` scope.
6. **Content not actually `Published`** — saving-as-draft doesn't trigger the webhook. Confirm the editor clicked Publish.
