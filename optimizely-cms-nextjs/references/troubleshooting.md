# Troubleshooting

Symptom-indexed list of failures and fixes, specific to the Next.js 16 + Optimizely SaaS CMS integration.

## Silent Failure Catalog

Most wiring mistakes in this stack produce **no error, no warning, just missing behaviour**. This table is the first place to look when "it renders blank", "editor can't see the new type", "content doesn't update", or "click-to-edit doesn't work":

| Symptom | Cause | Fix |
|---|---|---|
| Specific block renders blank, others render fine | Component missing from `initReactComponentRegistry.resolver` | Add it to the resolver in `lib/optimizely/init.ts` |
| New content type doesn't appear in CMS editor after `opti-push` | Schema file not under `./components/optimizely/**/*.tsx` | Move the file; re-run `opti-push` |
| Field not visible in CMS after `opti-push` | Schema change not pushed (editing component JSX doesn't push) | Run `npm run opti-push` |
| Header/Footer stays stale after CMS publish | `revalidateTag(tag)` missing `'max'` second arg, OR cache tag hardcoded instead of `getCacheTag(...)` | Use `revalidateTag(getCacheTag(CACHE_KEYS.HEADER, locale), 'max')` consistently in both fetcher and webhook |
| Batch publish doesn't trigger revalidation | Webhook missing `bulk.completed` topic | Add it to the webhook topic subscription |
| Every draft save triggers revalidation / hits quota | Webhook missing `status: { eq: "Published" }` filter | Add it to the webhook filters |
| Preview iframe redirects / loses query params | Middleware not excluding `/preview` | Add `/preview` to `shouldExclude` in `proxy.ts` |
| Preview page renders, but editor toolbar inert / no click-to-edit | `communicationinjector.js` not loaded or `OPTIMIZELY_CMS_HOST` unset | Verify env var, verify `<Script>` renders with correct URL |
| One specific field can't be clicked in preview but others can | `data-epi-edit="..."` value doesn't match the content-type property key exactly | Fix attribute value to match the property key character-for-character |
| Swedish visitor gets English page with no warning | CMS hasn't got a Swedish translation; Graph falls back to default | Expected behaviour — translate the content in CMS, or add a runtime check to log fallbacks |
| Prerender skipped a page that should be prerendered | Page's content type key not in `pageTypes` array in `getAllPagesPaths` | Add the key |
| Production build succeeds but all pages ISR-only | `getAllPagesPaths` caught an error and returned `[]` | Check build logs; usually env var missing in CI |
| `/api/revalidate` returns 404 | Middleware matcher includes `/api/*` | Confirm exclusion in `proxy.ts` config.matcher |
| Preview injector script 404s | `OPTIMIZELY_CMS_HOST` has trailing slash or wrong scheme | Use exact form `https://<instance>.cms.optimizely.com` |
| `'use cache'` throws at runtime with 'cacheComponents required' | `next.config.ts` missing `cacheComponents: true` | Add it |
| Build hangs with `HANGING_PROMISE_REJECTION` | `'use cache'` function threw during prerender | Wrap in try/catch inside the cached function, return null on failure |

Rule of thumb: when something isn't working and the console is quiet, the problem is almost certainly on this list.

## Production Hardening Checklist

The starter is a working reference implementation, not a production template. Items called out as gaps by the course author — address before shipping to real users:

- **Rate limit `/api/revalidate`.** The endpoint is secret-gated but otherwise unprotected. A leaked or brute-forced secret lets a bad actor flood `revalidatePath` calls and thrash the cache. Canonical fix: Upstash Ratelimit + Redis (IP-keyed sliding window). Alternative: IP allowlist Optimizely's webhook source ranges at the CDN/WAF.
- **Wire up error tracking.** No Sentry / equivalent is configured. Webhook errors currently end in a 500 JSON response and a `console.error` that nobody watches. Silent failures of revalidation mean editors publish, refresh, and wonder why nothing changed. Add Sentry (or Datadog, Honeybadger, etc.) around `/api/revalidate` at minimum.
- **Replace `console.*` with a structured logger.** Pino or Winston. Log at least: incoming docId, resolved URL type (SIMPLE vs hierarchical), resolved `urlWithLocale`, revalidation outcome (tag vs path, success/no-op), any error. Without this the webhook is a black box in prod.
- **Add tests.** Unit tests for the webhook's parsing + URL resolution logic (docId parse, SIMPLE vs hierarchical branch, header/footer vs page routing, malformed inputs). Post-deploy smoke test that hits a known page and verifies the CMS content is live.
- **Audit remaining `as any` casts.** The SDK has known type incompleteness in `GraphClient.request()` variables and `OptimizelyComponent`'s locale prop. Cast sites are marked `// Todo: Workaround for types for now` in the starter — each is a latent bug waiting for SDK types to tighten. Track them, upgrade the SDK when v1.1+ lands, remove casts where possible.
- **Rotate `OPTIMIZELY_REVALIDATE_SECRET` regularly.** Treat it like any other secret: vault storage, rotation schedule, scoped per-environment.
- **Test preview mode end-to-end before deploy.** The preview path involves middleware exclusion, CSP, env var, and the CMS-side Site URL setting. Easy to break one without noticing until an editor clicks Preview.

None of these are required for functional parity with the starter. All are required for prod-grade operations.

## Build / Registration

### "Cannot find content type 'HeroBlock'" at render time
The type is not in `initContentTypeRegistry`. Add `HeroBlockContentType` to the array in `lib/optimizely/init.ts`.

### Page renders blank for a specific content type
Component not in `initReactComponentRegistry.resolver`. Add it.

### New content type doesn't appear in the CMS editor
1. Confirm the `contentType()` call is exported from a file matching `./components/optimizely/**/*.tsx` (the glob in `optimizely.config.mjs`).
2. Run `npm run opti-push` — check output for the new type.
3. Check the CMS instance has accepted the push (look for errors in CLI output about data-loss; if so, review and rerun with `--force` if intended).

### `Error: cacheComponents is required for 'use cache' directive`
`next.config.ts` missing `cacheComponents: true`. Add it.

### Build hangs or errors with `HANGING_PROMISE_REJECTION`
A `'use cache'` function threw during static prerender. Add a `try/catch` inside the cached function returning `null`, or move the try/catch outside and ensure the caller handles rejection. See `data-fetching.md`.

### `initContentTypeRegistry` has no effect; registrations are lost
The init file is not imported at the app entry. Add `import '@/lib/optimizely/init'` to `app/layout.tsx` as a side-effect import.

### `generateStaticParams` returns an empty array in production
`getAllPagesPaths` caught an error (CMS unreachable at build time) and fell back to `[]`. App still works via ISR. To diagnose: check the build log for "Error generating static params". Verify `OPTIMIZELY_GRAPH_SINGLE_KEY` and `OPTIMIZELY_GRAPH_URL` are available at build time (they often live in `.env.local` which isn't used during CI builds — set them in the CI environment).

## Caching / Revalidation

### Content on published pages doesn't update after editor publishes
1. **Webhook not hitting the app.** Curl `/api/revalidate?cg_webhook_secret=...` to confirm; 401 means secret mismatch; 200 `{revalidated: true}` means the route works.
2. **`revalidateTag` missing second arg `'max'`.** Silent no-op for `cacheLife('max')` entries. Fix: `revalidateTag(tag, 'max')`.
3. **Wrong URL type handling.** If `_metadata.url.type` is `HIERARCHICAL` and `OPTIMIZELY_START_PAGE_URL` is wrong/unset, `revalidatePath` gets a path that doesn't match any rendered route.
4. **CDN in front of Next.js caching the HTML separately.** Configure CDN to honour Next.js cache tags or bypass HTML caching.

### Header/Footer updates, but pages still show stale blocks
Blocks sit inside pages, not header/footer. `revalidateTag` for HEADER/FOOTER won't invalidate page-level caches. Confirm the webhook's else-branch called `revalidatePath(urlWithLocale)` for the block's parent page.

### `revalidatePath` returns a "Page Not Found" from the webhook
The content's URL resolution failed. Log `content._metadata.url` to see what came back. Common causes: content has no default URL set; wrong locale; hierarchical routing not stripped.

### `'use cache'` ignores argument changes
The `'use cache'` key includes only function arguments. A variable captured from outer scope won't participate. Move all dynamic inputs to parameters.

### After `revalidateTag`, old content returns then gets fresh on a later request
Expected behaviour. `revalidateTag` marks entries stale but doesn't prefetch. The next request re-runs the fetch and re-caches. Subsequent requests hit the fresh cache.

### "Tag invalidation failed silently" in logs
Usually `cacheLife` duration mismatch. Always pass `'max'` to both `cacheLife` and `revalidateTag` for long-lived content.

## Locale / Middleware

### `/api/revalidate` returns 404
Middleware not excluding `/api/`. Check `proxy.ts`'s `config.matcher` regex and the `shouldExclude` function.

### URLs randomly redirect to `/en/...` or `/pl/...`
The user's Accept-Language header is being honoured on first visit. This is correct — subsequent visits use the cookie. If you want to force default locale regardless, add a stricter check in `getLocale`.

### Language switcher redirects to a page that doesn't exist in the new locale
CMS doesn't have the page translated. Either create the translation in CMS or handle the 404 gracefully — consider fetching `getContentByPath` with fallback locales.

### Middleware runs for static files
The matcher excludes `_next/static` and `_next/image` but not all file types. The `shouldExclude` function catches paths with `.` (has extension). If you add a static file type Next.js doesn't serve from `_next/`, include its pattern in `shouldExclude`.

## Preview

### Preview page renders but can't click to edit
Missing `<PreviewComponent />` or `communicationinjector.js` script. Check both are present in `app/preview/page.tsx`.

### Preview iframe shows blank / "refused to connect"
CSP header doesn't include `*.optimizely.com` in `frame-ancestors`. Check `next.config.ts`.

### Preview URL redirects before loading
Middleware not excluding `/preview`. Add to `shouldExclude` in `proxy.ts`.

### Draft images don't load in preview
Image URL doesn't include the preview token. Wrap image src with `getPreviewUtils(content).src(content.image)`.

### `OPTIMIZELY_CMS_HOST is undefined` in preview script URL
Environment variable not set at runtime. For `process.env.X` to work in a Server Component, it must be available in the server environment at render time (not only at build time).

## Visual Builder

### Component renders but drop zones missing in editor
`vb:grid` / `vb:row` / `vb:col` classes missing from the section's wrapper elements. Add them.

### Nested section inside an experience can't be clicked
Missing `{...pa(node)}` spread on the section wrapper. Add.

### Experience renders children twice
Likely passed both `content.composition.nodes` and the raw `content` to the renderer, or wrapped in two `OptimizelyComposition` calls.

### Display template's settings show as `undefined` in the component
1. `initDisplayTemplateRegistry([...])` missing the template.
2. The content type and display template `key` don't match (keys must align).
3. In Visual Builder, no display template variant selected for this instance — component receives `displaySettings: undefined`. Handle with defaults.

## Images

### `next/image` errors "hostname not configured"
Add the hostname to `remotePatterns` in `next.config.ts`.

### Images load but are full-resolution (no width optimization)
Custom loader didn't match the URL. Check `cloudinaryLoader` regex against the actual URL shape.

### Server-only imports in `loader.ts` break the bundle
The loader is `'use client'`. Remove server-only imports.

## SDK Type Issues

### `OptimizelyComponent` rejects `locale` prop
Known SDK types limitation. Cast:
```ts
const OptimizelyComponentWithLocale = OptimizelyComponent as React.ComponentType<{
  content: any
  locale: string
}>
```

### `client.request()` variables typed as `never`
Known SDK types limitation. Use `as any` on the variables:
```ts
await client.request(query, { foo: 'bar' } as any)
```

### `ContentProps<typeof XContentType>` infers `any` for nested arrays
Usually a missing `items.allowedTypes` on the schema — without it, the SDK can't infer the child type.

## CLI (`opti-push`)

### `opti-push` fails with "authentication failed"
`OPTIMIZELY_CMS_CLIENT_ID` or `OPTIMIZELY_CMS_CLIENT_SECRET` wrong/missing. Regenerate in CMS → Settings → API Keys.

### `opti-push` errors about property removal ("would cause data loss")
The schema removed a property that has CMS data. Options:
1. Restore the property in code if the data matters.
2. Run `npm run opti-push-data-loss` to force-drop (destructive; never without user confirmation).

### `opti-push` reports stale types not in code
Properties removed from code that still exist in CMS. Run `--force` to sync drops, or add them back in code.

### CLI can't find content types in my glob
The glob in `optimizely.config.mjs` is relative to the file's location. Use `./components/optimizely/**/*.tsx`, not absolute paths. Confirm the file contains a `contentType()` call and exports it.

## Env vars

### Preview works locally but not in production
`OPTIMIZELY_CMS_HOST` or `OPTIMIZELY_REVALIDATE_SECRET` missing in production env config. Set in your hosting platform.

### Deploy builds succeed but pages 404 at runtime
`OPTIMIZELY_GRAPH_SINGLE_KEY` missing at runtime. In hosting platforms that distinguish build-time vs runtime envs, set it in both.
