# Project Setup

All configuration files needed to stand up a Next.js 16 app against `@optimizely/cms-sdk` v2, sized to deploy on Optimizely Frontend Hosting (DXP).

## Dependencies

```json
{
  "engines": { "node": ">=18.18.0" },
  "dependencies": {
    "@optimizely/cms-sdk": "^2.0.0",
    "next": "16.1.1",
    "next-intl": "^4.12.0",
    "react": "19.2.3",
    "react-dom": "19.2.3"
  },
  "devDependencies": {
    "@types/node": "^20",
    "@types/react": "^19",
    "@types/react-dom": "^19",
    "typescript": "^5"
  }
}
```

Optional dependencies, present when running on DXP:

```json
{
  "dependencies": {
    "@azure/identity": "^4.13.1",
    "@redis/entraid": "^5.12.1",
    "redis": "^5.12.1"
  }
}
```

Notes:
- React 19 is required by Next.js 16.
- `next-intl` handles locale routing — no bespoke middleware or Negotiator setup.
- Azure / Redis packages are only needed for the DXP shared cache handler; local dev falls back to in-memory.

## package.json scripts

```json
{
  "scripts": {
    "dev": "next dev --experimental-https",
    "build": "next build",
    "start": "next start",
    "lint": "eslint",
    "cms:login": "npx @optimizely/cms-cli@^2.0.0 login",
    "cms:push-config": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs",
    "cms:push-config-force": "npx @optimizely/cms-cli@^2.0.0 config push ./optimizely.config.mjs --force",
    "cms:pull-config": "npx @optimizely/cms-cli@^2.0.0 config pull --output ./src/content-types --group",
    "preinstall": "npx only-allow npm"
  },
  "packageManager": "npm@11.8.0"
}
```

- `dev --experimental-https` issues a local cert so preview mode works against `OPTIMIZELY_CMS_URL` (the CMS will reject mixed-content embeds).
- Pin the CLI major version (`@^2.0.0`) so `npx` doesn't unexpectedly upgrade mid-project.
- `preinstall` with `only-allow npm` blocks accidental `pnpm`/`yarn` installs that have caused SWC segfaults in this repo's history.
- `cms:push-config-force` uses `--force` which drops CMS-side properties not present in code. Never run without explicit user confirmation — can destroy editorial work.

## next.config.ts

```ts
import { resolve } from 'node:path';
import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const withNextIntl = createNextIntlPlugin('./src/i18n/request.ts');

const nextConfig: NextConfig = {
  // Enables `'use cache'` directive and auto-PPR. Required for the
  // localized catch-all (/[locale]/[[...slug]]) and the cache profile in
  // get-page.ts to compose correctly.
  cacheComponents: true,

  // Optimizely DXP shared Redis cache handler. With cacheMaxMemorySize: 0
  // Next.js does not keep a duplicate in-process LRU; the handler (Redis in
  // production, in-memory Map locally) is the sole source of truth. This is
  // what lets revalidateTag / revalidatePath reach every replica behind
  // the load balancer.
  cacheHandler: resolve(process.cwd(), 'cache-handler.mjs'),
  cacheMaxMemorySize: 0,

  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '*.cms.optimizely.com' },
      { protocol: 'https', hostname: 'cdn.optimizely.com' },
      { protocol: 'https', hostname: '*.cmp.optimizely.com' },
    ],
  },

  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'Permissions-Policy', value: 'unload=(self)' },
        ],
      },
    ];
  },
};

export default withNextIntl(nextConfig);
```

Critical pieces:
- `cacheComponents: true` — enables the `'use cache'` directive. Without it, `getPageContent` errors at runtime.
- `cacheHandler` + `cacheMaxMemorySize: 0` — sends every cache hit through the Redis handler. Without `cacheMaxMemorySize: 0`, Next.js keeps a duplicate in-process copy, and `revalidateTag` calls on one replica don't reach the others.
- `withNextIntl` — required wrapper from `next-intl/plugin` that wires translation file loading into the build.
- `remotePatterns` covers the Optimizely-hosted image hosts. Add more as needed (Cloudinary, etc.) but no custom loader is required for the default case.

## tsconfig.json

```jsonc
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

`@/*` maps to `./src/*` — used throughout the codebase. Don't change this without updating every import.

## optimizely.config.mjs

```js
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

`buildConfig` accepts string globs or explicit file paths — **not** imported content-type objects. The CLI walks those paths at push time and extracts every `contentType()` / `displayTemplate()` export. See the `optimizely-cms-content-types` skill for property-group rules and glob negation.

## .env (template)

```ini
# Optimizely CMS API Credentials
# CMS → Settings → API Keys → Manage Content
OPTIMIZELY_CMS_CLIENT_ID=
OPTIMIZELY_CMS_CLIENT_SECRET=

# Optimizely Graph Credentials (provisioned by DXP at deploy)
OPTIMIZELY_GRAPH_SINGLE_KEY=

# Graph gateway. Locally include the full path; in DXP just the base URL.
# getGraphGatewayUrl() in src/lib/config.ts normalises both shapes.
OPTIMIZELY_GRAPH_GATEWAY=https://cg.optimizely.com
OPTIMIZELY_GRAPH_PATH=/content/v2

# CMS instance URL — used by the preview route to load communicationinjector.js
OPTIMIZELY_CMS_URL=

# Public site origin (no trailing slash). Used for canonical URLs, sitemap,
# robots.txt sitemap reference. Defaults to http://localhost:3000 locally.
NEXT_PUBLIC_SITE_URL=

# Optimizely Web Experimentation snippet ID (digits-only).
# Leave blank to skip rendering the snippet entirely.
OPTIMIZELY_WEB_EXP_SNIPPET_ID=

# Deployment Credentials (for deploy.ps1)
# PaaS Portal → API tab → Deployment API Credentials
OPTI_PROJECT_ID=
OPTI_CLIENT_KEY=
OPTI_CLIENT_SECRET=
OPTI_TARGET_ENV=Test2

# ──────────────────────────────────────────────────────────────────
# DXP-provisioned variables — leave blank locally
# ──────────────────────────────────────────────────────────────────

# Redis cache handler (cache-handler.mjs)
REDIS_URL=
OPTIMIZELY_DXP_DEPLOYMENT_ID=
AZURE_CLIENT_ID=

# CDN purge (Cloud Platform Services edge-cache API)
OPTIMIZELY_CLOUDPLATFORM_API_URL=
OPTIMIZELY_CLOUDPLATFORM_API_RESOURCE_ID=

# Graph webhook receiver (/hooks/graph)
OPTIMIZELY_GRAPH_CALLBACK_APIKEY=
OPTIMIZELY_SITE_HOSTNAME=
OPTIMIZELY_GRAPH_APP_KEY=
OPTIMIZELY_GRAPH_SECRET=
```

### Credentials gotcha

`OPTIMIZELY_CMS_CLIENT_SECRET` is shown **once** in the CMS UI and is non-recoverable after the dialog closes. Copy it into `.env` immediately. If lost, rotate the key in CMS → Settings → API Keys and update every environment.

### Local-vs-DXP env shape

`OPTIMIZELY_GRAPH_GATEWAY` has different shapes in different environments:
- **Locally**: full URL including path — `https://cg.optimizely.com/content/v2`
- **In DXP**: base URL only — `https://cg.optimizely.com`

`getGraphGatewayUrl()` in `src/lib/config.ts` normalises both. Always call it instead of reading the env var directly:

```ts
// src/lib/config.ts
export function getGraphGatewayUrl(): string {
  const gateway = process.env.OPTIMIZELY_GRAPH_GATEWAY;
  const graphPath = process.env.OPTIMIZELY_GRAPH_PATH || '/content/v2';
  if (!gateway) throw new Error('OPTIMIZELY_GRAPH_GATEWAY is not set');
  if (gateway.endsWith(graphPath)) return gateway;
  return `${gateway.replace(/\/+$/, '')}${graphPath}`;
}
```

## Shared Redis cache handler

`cache-handler.mjs` lives in the repo root (not under `src/`) and is referenced by `next.config.ts`'s `cacheHandler`. The handler:

1. Tries to connect to Redis via `REDIS_URL` using EntraId managed-identity auth.
2. On connection failure, falls back to an in-memory `Map` and retries Redis after 60s.
3. Namespaces cache keys with `nextjs:${OPTIMIZELY_DXP_DEPLOYMENT_ID}:` so deployments don't collide.
4. Implements `revalidateTag` by deleting keys for `_N_T_<path>` tags (Next.js's path-tag convention).

Skeleton:

```js
// cache-handler.mjs (abbreviated — see actual file for full Entra/Redis wiring)
import { createCluster } from 'redis';
import { EntraIdCredentialsProviderFactory, REDIS_SCOPE_DEFAULT } from '@redis/entraid';
import { ManagedIdentityCredential } from '@azure/identity';

const deploymentId = process.env.OPTIMIZELY_DXP_DEPLOYMENT_ID ?? 'default';
const CACHE_PREFIX = `nextjs:${deploymentId}:`;

const memoryCache = new Map();
let cluster = null;
let connectionFailedUntil = 0;

async function getClient() {
  if (Date.now() < connectionFailedUntil) return null;
  if (cluster?.isOpen) return cluster;
  if (!process.env.REDIS_URL) return null;
  try {
    return await connectToRedis(process.env.REDIS_URL);
  } catch (err) {
    console.warn('Redis unavailable, falling back to in-memory:', err?.message);
    connectionFailedUntil = Date.now() + 60_000;
    return null;
  }
}

export default class CacheHandler {
  async get(key) {
    const redis = await getClient();
    if (redis) { /* … redis.get(prefix+key) … */ }
    return memoryCache.get(key) ?? null;
  }
  async set(key, value, context) { /* … redis.set with TTL, fallback to memoryCache */ }
  async revalidateTag(tags) { /* … delete keys matching _N_T_ prefix */ }
  resetRequestCache() { /* no-op for shared cache */ }
}
```

Keep this file byte-for-byte aligned with Optimizely's reference implementation (`docs/isr-documentation.md` §2.2) so future updates remain trivially mergeable. Do not ESLint-clean it.

### Why `cacheMaxMemorySize: 0`

With the shared handler installed, Next.js wants to mirror the cache into an in-process LRU as well. That would mean:
- Replica A reads stale data because its in-process cache wasn't invalidated when Replica B did the `revalidateTag` call.
- Replica B serves fresh data; Replica A serves stale data; load balancer makes this look like random staleness.

`cacheMaxMemorySize: 0` disables that in-process mirror — every read goes through `cache-handler.mjs`, which talks to the shared Redis. One source of truth.

## CI/CD ordering — `cms:push-config` must run BEFORE `next build`

```
CI pipeline order:
  1. npm ci
  2. npm run cms:push-config       # sync schemas to CMS
  3. next build                     # build now sees the CMS-known types
```

Running `cms:push-config` after or concurrent with `next build` is a silent bug factory: the build's data fetchers can read content whose schema doesn't yet exist in CMS, producing incomplete or empty results that get baked into prerendered HTML (or in this repo's case, into the first Redis cache fill after deploy).

### Which schema changes require `cms:push-config`

Required (schema needs pushing):
- New content type added
- Property added, renamed, or removed on an existing type
- `displayName` changed on a type or property
- `localized` toggled on a property
- `allowedTypes` / `restrictedTypes` changed
- New display template added or modified

Not required (purely runtime/React concerns):
- React component JSX edits
- CSS / Tailwind class changes
- New entries in `initReactComponentRegistry.resolver` (runtime-only)
- Translation file edits

If unsure, run `cms:push-config` — it's idempotent when nothing has changed.

## Post-install checklist

1. Fill `.env` with credentials.
2. Register at least one content type in `src/optimizely.ts` (including `BlankExperienceContentType` + `BlankSectionContentType` if using Visual Builder).
3. `npm run cms:push-config` — seeds the CMS with your types.
4. Configure the CMS webhook to POST `https://<your-domain>/hooks/graph` with `x-api-key: <OPTIMIZELY_GRAPH_CALLBACK_APIKEY>`.
5. Confirm the CMS Site URL points at your deployed domain (for the preview communication injector to target the correct host).

## Directory layout

```
src/
  app/
    layout.tsx                       — imports '@/optimizely' (side-effect)
    [locale]/
      layout.tsx
      [[...slug]]/page.tsx           — optional catch-all
    preview/page.tsx                 — withAppContext-wrapped preview
    hooks/graph/route.ts             — POST webhook
    sitemap.ts robots.ts
    diagnostics/ debug/              — dev-only inspection routes

  components/
    pages/ blocks/ elements/ experiences/ layout/ ui/
    layout/CommunicationInjector.tsx
    layout/PreviewError.tsx

  content-types/                     — contentType() definitions
  display-templates/                 — displayTemplate() definitions

  lib/
    optimizely/
      get-page.ts all-pages.ts all-content-paths.ts get-articles-under.ts
      navigation.ts
    cache/cache-keys.ts
    cdn-cache.ts config.ts seo.ts rich-text.ts

  i18n/
    routing.ts request.ts navigation.ts

  optimizely.ts                      — SDK init entry
  proxy.ts                           — next-intl middleware

cache-handler.mjs                    — Redis-backed shared cache
optimizely.config.mjs
next.config.ts
messages/                            — en.json no.json sv.json …
```

The `src/content-types/` and `src/display-templates/` paths are what the CLI scans via the `components` array in `optimizely.config.mjs`. Schema files live there (or `src/components/**/*.tsx` if you co-locate schema with React component) — wherever you put them, the path must match the glob.
