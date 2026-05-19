# Troubleshooting

Symptom-indexed list of failures and fixes, specific to the Next.js 16 + Optimizely SaaS CMS v2 + DXP integration.

## Silent Failure Catalog

Most wiring mistakes in this stack produce **no error, no warning, just missing behaviour**. First place to look when "it renders blank", "editor can't see the new type", "content doesn't update", or "click-to-edit doesn't work":

| Symptom | Cause | Fix |
|---|---|---|
| Specific block renders blank, others render fine | Component missing from `initReactComponentRegistry.resolver` | Add it in `src/optimizely.ts` |
| New content type doesn't appear in CMS editor after `cms:push-config` | Schema file not matched by `components` glob in `optimizely.config.mjs` | Add the file path or extend the glob |
| Field not visible in CMS after `cms:push-config` | Schema change not pushed (editing component JSX doesn't push) | Run `npm run cms:push-config` |
| Visual Builder section content renders blank | `BlankSectionContentType` not in `initContentTypeRegistry` | Add it (and `BlankExperienceContentType`) |
| Page stays stale after CMS publish | `cacheTag(getPageTag(slug))` mismatched with webhook's tag composition, OR `revalidateTag` missing `'max'` second arg | Use `getPageTag()` consistently; pair `cacheLife('max')` with `revalidateTag(tag, 'max')` |
| Webhook fires but nothing revalidates | `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` missing in DXP env → 401 every request | Set env var in DXP; matches the value in CMS webhook config |
| Sitemap stays stale | `revalidateTag(CACHE_KEYS.PATHS, 'hours')` missing in webhook or `'hours'` second arg missing | Pair with `cacheLife('hours')` profile |
| Article listing stays stale after new article published | Webhook missing ancestor-prefix `revalidateTag(getArticlesUnderTag(...), 'max')` loop | Add the for-loop over `path.split('/').filter(Boolean)` |
| Preview iframe redirects / loses query params | next-intl middleware not excluding `/preview` | Verify `preview` is in `matcher` exclusion |
| Preview page renders but editor toolbar inert / no click-to-edit | `OPTIMIZELY_CMS_URL` wrong, missing, or has trailing slash | Set to exact `https://<instance>.cms.optimizely.com` |
| Preview content has no preview token (drafts won't load images) | Route missing `withAppContext(Page)` wrapper | Wrap the default export |
| One field can't be clicked in preview but others can | `pa('foo')` / `data-epi-edit="foo"` doesn't match the schema property key character-for-character | Fix the attribute value |
| Page returns 200 OK on a 404 URL, gets CDN-cached for 30 days | `notFound()` called from inside `<Suspense>` under `cacheComponents` | Move `notFound()` above the Suspense and call in `generateMetadata` |
| Build hangs with `HANGING_PROMISE_REJECTION` | `'use cache'` function threw during prerender | Wrap external calls in try/catch, return null on failure |
| `revalidateTag` works on one replica, not others | `cache-handler.mjs` not wired, OR `cacheMaxMemorySize` not set to 0 | Configure both in `next.config.ts` |
| Webhook URL gets locale-prefixed in CMS | Middleware matcher missing `hooks` exclusion | Add `hooks` to the matcher exclusion list |
| `cms:push-config` silently skips new file | File path not in `components` array or not matched by glob | Verify the path |
| Translations missing in preview render | Locale bridge in preview route missing or wrong | Validate `params.loc` against `routing.locales`, `setRequestLocale`, wrap in `<NextIntlClientProvider>` |
| In-process LRU and Redis cache diverge | Missing `cacheMaxMemorySize: 0` in next.config.ts | Add it |

Rule of thumb: when something isn't working and the console is quiet, the problem is almost certainly on this list.

## Production Hardening Checklist

The reference implementation is functional but not production-hardened. Items to address before shipping to real users:

- **Rate-limit `/hooks/graph`.** The endpoint is `x-api-key`-gated but otherwise unprotected. A leaked or brute-forced key lets a bad actor flood `revalidatePath` calls and thrash the cache. Canonical fix: Upstash Ratelimit + Redis (IP-keyed sliding window). Alternative: IP allowlist Optimizely's webhook source ranges at the WAF/CDN layer.
- **Wire up error tracking.** No Sentry / equivalent is configured. Webhook errors currently log to `console.error` and nobody watches; silent failures of revalidation mean editors publish, refresh, and wonder why nothing changed.
- **Replace `console.*` with a structured logger** (Pino, Winston). Log: incoming docId, resolved path, revalidation outcome (tag vs path, success/no-op), CDN purge result, any error. Without structured logs, the webhook is a black box in prod.
- **Add tests for the webhook** (docId parsing, URL resolution, ancestor-prefix invalidation). Enough branches to warrant coverage; nothing exists today.
- **Add tests for `getPageContent` error paths.** Confirm null-on-failure rather than throw, confirm placeholder slug short-circuits.
- **Audit the SDK type-system gaps.** `OptimizelyComponent` doesn't formally accept extra props like `locale`; `client.request()` variables type as `never` without `as any`. These are SDK limitations — track them and upgrade when the SDK tightens.
- **Rotate `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` regularly.** Treat it like any secret: vault storage, rotation schedule, scoped per-environment.
- **Test preview end-to-end before deploy.** The preview path involves middleware exclusion, CSP, env vars, CMS-side Site URL setting. Easy to break one without noticing until an editor clicks Preview.

None required for functional parity. All required for prod-grade operations.

## Build / Registration

### "Cannot find content type 'HeroBlock'" at render time
The type is not in `initContentTypeRegistry`. Add `HeroBlockCT` to the array in `src/optimizely.ts`.

### Page renders blank for a specific content type
Component not in `initReactComponentRegistry.resolver`. Add it.

### New content type doesn't appear in the CMS editor
1. Confirm the file path is in `optimizely.config.mjs`'s `components` array (or matched by a glob).
2. Run `npm run cms:push-config` and check output for the new type.
3. Check the CMS instance accepted the push (look for data-loss warnings; if expected, rerun with `--force`).

### `Error: cacheComponents is required for 'use cache' directive`
`next.config.ts` missing `cacheComponents: true`. Add it.

### Build hangs or errors with `HANGING_PROMISE_REJECTION`
A `'use cache'` function threw during static prerender. Add `try/catch` inside the cached function returning `null`. See `references/data-fetching.md`.

### `initContentTypeRegistry` has no effect
The init file isn't imported at app entry. Add `import '@/optimizely'` to `src/app/layout.tsx` as a side-effect import.

### `generateStaticParams` returns the placeholder per locale instead of real paths
This is intentional in this project — see `references/static-generation.md`. Pages fill into the Redis cache on first request. If you want real prerender, switch the implementation (and accept that builds become coupled to Graph availability).

## Caching / Revalidation

### Content on published pages doesn't update after editor publishes
1. **Webhook not hitting the app.** Check DXP access logs for `POST /hooks/graph`. If nothing, the CMS webhook config is wrong.
2. **`x-api-key` mismatch.** 401 in logs means `OPTIMIZELY_GRAPH_CALLBACK_APIKEY` is missing or wrong. Confirm value matches CMS-side config.
3. **`revalidateTag` missing `'max'` second arg.** Silent no-op for `cacheLife('max')` entries. Always pass `'max'`.
4. **Redis cache handler not wired.** Without it, `revalidateTag` runs against one replica's in-process cache; other replicas serve stale.
5. **CDN cache holding stale HTML.** Verify `purgeCdnCache` runs and Cloud Platform Services API accepts the request (look for `[hooks] CDN cache purge` log).

### Article listing stays stale after publish
Webhook must invalidate every ancestor prefix:
```ts
for (let i = 1; i < segments.length; i++) {
  const parent = `/${segments.slice(0, i).join('/')}/`;
  revalidateTag(getArticlesUnderTag(parent, locale), 'max');
}
```
Missing this loop = listings don't refresh when descendants publish.

### Sitemap stays stale
Webhook must `revalidateTag(CACHE_KEYS.PATHS, 'hours')`. Without it, the sitemap waits for the `cacheLife('hours')` TTL to expire.

### `revalidatePath` returns no error but page still stale
`revalidatePath` marks the entry stale; it doesn't prefetch. The next request re-fills. If subsequent requests still see stale, the CDN layer is caching ahead of Next.js — check CDN purge ran.

### `'use cache'` ignores argument changes
The `'use cache'` key includes only function arguments. A variable captured from outer scope won't participate. Move all dynamic inputs to parameters.

### "Tag invalidation failed silently" / nothing in logs
Usually `cacheLife` duration mismatch. Always match: `cacheLife('max')` + `revalidateTag(tag, 'max')`; `cacheLife('hours')` + `revalidateTag(tag, 'hours')`.

## Locale / Middleware

### `/hooks/graph` returns 404 or gets locale-prefixed
Middleware not excluding `hooks`. Verify the matcher in `src/proxy.ts`:
```ts
matcher: ['/((?!api|hooks|debug|diagnostics|preview|_next|_vercel|.*\\..*).*)'],
```

### Visiting `/` shows the default locale page (or 404 on a fresh deploy)
next-intl's `localePrefix: 'always'` redirects `/` to `/<defaultLocale>`. First request to `/no/` after deploy is a cache miss and pays Graph latency; subsequent requests are cache HITs. If `/` redirects to a 404, the default locale's page isn't in CMS — publish it.

### Language switcher redirects to a page that doesn't exist in the new locale
The CMS doesn't have the page translated. Either create the translation or handle the 404 gracefully (consider fetching `getContentByPath` with locale fallbacks).

### Middleware runs for static files
The matcher excludes `_next/static` and `_next/image` and `.*\\..*` (any path with an extension). If a non-standard static asset slips through, add its prefix to the matcher.

### `setRequestLocale` warnings in dev
The locale layout must call `setRequestLocale(locale)` for static rendering to work under `cacheComponents`. Without it, the layout falls back to dynamic.

## Preview

### Preview page renders but can't click to edit
Missing `<PreviewComponent />` or `communicationinjector.js` script. Check both are present in `src/app/preview/page.tsx`.

### Preview iframe shows blank / "refused to connect"
CSP `frame-ancestors` doesn't include `*.optimizely.com`. Check `next.config.ts` headers (or DXP's edge headers).

### Preview URL redirects before loading
Middleware not excluding `/preview`. Verify `preview` is in `matcher`.

### Draft images don't load in preview
Component bypassing `getPreviewUtils.src()`. Use `src(content.image)` not `content.image.url.default`.

### `OPTIMIZELY_CMS_URL is undefined` in preview script URL
Env var not set at runtime. For `process.env.X` in a Server Component, it must be in the server runtime env (not only build-time).

### Preview body errors before retry completes
"No content found for key" — content not yet indexed. The retry loop handles transient cases (3× 200ms). Persistent failures usually mean the publish itself didn't complete in CMS.

### `PreviewError` shows "Missing Content Type"
A content type the CMS references isn't in `initContentTypeRegistry`. Add it. Often happens after pulling new content from CMS that uses a type not yet defined in code.

### `withAppContext` errors at module load
`withAppContext` must wrap the route's default export, not be applied inside the JSX. Apply as `export default withAppContext(Page)`.

## Visual Builder

### Component renders but drop zones missing in editor
`vb:grid` / `vb:row` / `vb:col` classes missing from the section's wrapper elements. Add them.

### Nested section inside an experience can't be clicked
Missing `{...pa(node)}` on the section wrapper.

### Experience renders children twice
Likely passed both `content.composition.nodes` and the raw `content` to the renderer, or wrapped in two `OptimizelyComposition` calls.

### Display template's settings show as `undefined` in the component
1. `initDisplayTemplateRegistry([...])` missing the template.
2. Content type key and display template `contentType` field don't match.
3. The editor hasn't selected a variant — `displaySettings` is `undefined` by default. Handle with fallbacks.

### Row/column display settings not flowing through
`StructureContainerProps.displaySettings` is populated only when a `displayTemplate({ nodeType: 'row' | 'column' })` matches. Verify the template is registered and the `nodeType` matches.

## Images

### `next/image` errors "hostname not configured"
Add the hostname to `remotePatterns` in `next.config.ts`. Default config covers `*.cms.optimizely.com`, `cdn.optimizely.com`, `*.cmp.optimizely.com`.

### Images full-resolution everywhere
Missing `sizes` prop on `<Image>`. Add it so Next.js knows which widths to generate.

### SVGs are rejected
`next/image` blocks SVG by default. Use plain `<img>` (or enable `dangerouslyAllowSVG` with caution).

## SDK Type Issues

### `OptimizelyComponent` rejects `locale` prop
Known SDK limitation. Cast:
```ts
const TypedComponent = OptimizelyComponent as React.ComponentType<{
  content: unknown;
  locale: string;
}>;
```

### `client.request()` variables typed as `never`
Known SDK limitation. Use `as any`:
```ts
await client.request(query, { foo: 'bar' } as any);
```

### `ContentProps<typeof XCT>` infers `any` for nested arrays
Usually a missing `items.allowedTypes` on the schema — without it, the SDK can't infer the child type. Add `allowedTypes` (also fixes the `maxFragmentThreshold` warning).

### `[optimizely-cms-sdk] Fragment "X" generated N inner fragments (limit: 100)`
v2 warning when a content type emits too many GraphQL fragments. Fix by adding `allowedTypes` / `restrictedTypes` to the offending `content` or `contentReference` property. See content-types skill's troubleshooting.

## CLI (`cms:push-config`)

### `cms:push-config` fails with "authentication failed"
`OPTIMIZELY_CMS_CLIENT_ID` / `OPTIMIZELY_CMS_CLIENT_SECRET` wrong or missing. Regenerate in CMS → Settings → API Keys.

### `cms:push-config` errors about property removal ("would cause data loss")
The schema removed a property that has CMS data. Options:
1. Restore the property in code if the data matters.
2. Run `npm run cms:push-config-force` to force-drop (destructive — never without user confirmation).

### `cms:push-config` reports stale types not in code
Properties removed from code that still exist in CMS. `--force` syncs the drops, or add them back in code.

### CLI can't find content types in glob
The glob in `optimizely.config.mjs` is relative to the file's location. Confirm the file contains a `contentType()` call and the path matches the glob.

## DXP / Hosting

### Cache works locally but stale in production
1. `REDIS_URL` not set in DXP env → handler falls back to in-memory per-replica.
2. `cacheMaxMemorySize: 0` missing → in-process LRU shadows the Redis handler.
3. `OPTIMIZELY_DXP_DEPLOYMENT_ID` missing → cache keys collide across deployments.

### CDN purge fails silently
`OPTIMIZELY_CLOUDPLATFORM_API_URL` / `OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID` missing → `purgeCdnCache` warns and no-ops. Managed identity must have `edge-cache/.default` scope on the resource.

### Build succeeds but production routes 404
Two common causes:
1. Locale not in `routing.locales` and the URL uses an unrecognised prefix.
2. `getPageContent` failed for that route (Graph unreachable, content unpublished). Cache fills on first successful fetch; check whether the request reached `getContentByPath`.

### Deploy succeeds but `/preview` 404s
`/preview/page.tsx` missing or not exported correctly. Verify the file exists and exports `withAppContext(Page)` as default.

## Env vars

### Preview works locally but not in production
`OPTIMIZELY_CMS_URL` missing in DXP. Set it; redeploy.

### Webhook 401s in production but works locally
`OPTIMIZELY_GRAPH_CALLBACK_APIKEY` mismatch between DXP env and CMS webhook config. Rotate and update both.

### `getGraphGatewayUrl()` throws "OPTIMIZELY_GRAPH_GATEWAY is not set"
The env var is missing. Locally, set to full URL `https://cg.optimizely.com/content/v2`. In DXP, the platform sets the base URL `https://cg.optimizely.com` and `getGraphGatewayUrl()` appends the path.

## Diagnostics routes

The repo includes `src/app/diagnostics/` and `src/app/debug/` routes for inspecting Graph/SDK state. These are:
- Excluded from the next-intl middleware (`debug`, `diagnostics` in matcher)
- Disallowed in `robots.ts`
- Useful when troubleshooting "is the SDK seeing my registered types", "is the Graph query I think running actually running", etc.

When `PreviewError` surfaces a query, copy it into a diagnostics page (or external GraphiQL) to verify it runs cleanly against the live Graph. Don't ship diagnostics routes to a public-facing site without auth.
