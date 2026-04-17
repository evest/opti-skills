# Project Setup

All configuration files needed to stand up a Next.js 16 app against `@optimizely/cms-sdk` v1.0.0.

## Dependencies

```json
{
  "dependencies": {
    "@optimizely/cms-sdk": "^1.0.0",
    "next": "16.1.6",
    "react": "19.2.4",
    "react-dom": "19.2.4",
    "negotiator": "^1.0.0"
  },
  "devDependencies": {
    "@optimizely/cms-cli": "^1.0.0",
    "@types/negotiator": "^0.6.3",
    "@types/node": "^20",
    "@types/react": "19.2.14",
    "@types/react-dom": "19.2.3",
    "typescript": "^5"
  },
  "overrides": {
    "@types/react":     "19.2.14",
    "@types/react-dom": "19.2.3"
  }
}
```

Notes:
- Pin React types in `overrides` — Next.js 16 App Router breaks on version mismatches between `@types/react` and the actual React 19.
- `negotiator` is only needed if you implement locale-aware middleware (see `locale-routing.md`).

## package.json scripts

```json
{
  "scripts": {
    "dev":                 "next dev",
    "dev-https":           "next dev --experimental-https",
    "build":               "next build",
    "start":               "next start",
    "opti-push":           "npx @optimizely/cms-cli@latest config push optimizely.config.mjs",
    "opti-push-data-loss": "npx @optimizely/cms-cli@latest config push optimizely.config.mjs --force"
  }
}
```

- `dev-https` is useful when testing preview mode locally, because the CMS's communication injector expects HTTPS in production-like setups.
- `opti-push-data-loss` uses `--force` which drops CMS-side properties not present in code. Never run without explicit user confirmation — can destroy editorial work.

## optimizely.config.mjs

```js
import { buildConfig } from '@optimizely/cms-sdk'

export default buildConfig({
  components: ['./components/optimizely/**/*.tsx'],
  // Optional: editor-side property groups (sister skill covers group usage)
  // propertyGroups: [
  //   { key: 'content',  displayName: 'Content',  sortOrder: 1 },
  //   { key: 'seo',      displayName: 'SEO',      sortOrder: 2 },
  //   { key: 'settings', displayName: 'Settings', sortOrder: 3 },
  // ],
})
```

`buildConfig` accepts string glob paths, **not** imported content-type objects. The CLI walks those globs at push time and extracts every `contentType()` / `displayTemplate()` export.

## next.config.ts

```ts
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  cacheComponents: true,    // required for 'use cache' in server components
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: '*.cms.optimizely.com' },
      { protocol: 'https', hostname: '*.cmstest.optimizely.com' },
      { protocol: 'https', hostname: '*.optimizely.com', port: '', pathname: '/**' },
      { protocol: 'https', hostname: 'res.cloudinary.com' },
    ],
    loader: 'custom',
    loaderFile: './lib/image/loader.ts',
  },
  async headers() {
    return [{
      source: '/:path*',
      headers: [
        { key: 'X-Frame-Options',        value: 'SAMEORIGIN' },
        { key: 'Content-Security-Policy', value: "frame-ancestors 'self' *.optimizely.com" },
      ],
    }]
  },
}

export default nextConfig
```

Critical pieces:
- `cacheComponents: true` — enables the `'use cache'` directive. Without it, page fetchers will error at runtime.
- `frame-ancestors 'self' *.optimizely.com` — allows the CMS preview iframe to embed your site. Without this CSP, preview mode shows a blank iframe with console errors.
- The `*.optimizely.com` wildcards in `remotePatterns` cover the DAM asset hosts that Optimizely serves from. Cloudinary is for the stock starter media; drop if unused.

## tsconfig.json

Key options:

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
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

The `@/*` path alias is used everywhere in the example app — keep it.

## .env (template)

```
OPTIMIZELY_GRAPH_SINGLE_KEY=<from CMS > Settings > API Keys>
OPTIMIZELY_CMS_CLIENT_ID=<from CMS > Settings > API Keys (Create API key)>
OPTIMIZELY_CMS_CLIENT_SECRET=<same panel>
OPTIMIZELY_CMS_HOST=https://<instance>.cms.optimizely.com
OPTIMIZELY_GRAPH_URL=https://cg.optimizely.com/content/v2
OPTIMIZELY_REVALIDATE_SECRET=<random high-entropy string>
OPTIMIZELY_START_PAGE_URL=/start-page
```

Notes:
- `OPTIMIZELY_GRAPH_URL` is effectively a constant (`https://cg.optimizely.com/content/v2`) except when pointing at a non-prod Graph instance.
- `OPTIMIZELY_REVALIDATE_SECRET` — generate fresh; the CMS webhook URL becomes `/api/revalidate?cg_webhook_secret=<value>`.
- `OPTIMIZELY_START_PAGE_URL` — the Start Page's real path in Optimizely (which is not `/`). Only needed for hierarchical URL routing. On older or non-standard CMS SaaS instances the hierarchical URLs can emit unexpected prefixes; this env var is the escape hatch. If you run SIMPLE routing only, you can leave this blank.
- The starter repo ships `.env` (not `.env.example`) into git-ignored state. In a new project, create both `.env.example` (committed, no secrets) and `.env.local` (ignored).

### Credentials gotcha

**`OPTIMIZELY_CMS_CLIENT_SECRET` is shown once in the CMS UI and is non-recoverable after the dialog closes.** Copy it into `.env.local` immediately. If lost, you have to rotate the key in CMS → Settings → API Keys and update every environment that uses it.

## CI/CD ordering — `opti-push` must run BEFORE `next build`

```
CI pipeline order:
  1. npm ci
  2. npm run opti-push        # sync schemas to CMS
  3. next build                # now the CMS has every type the build expects
```

Running `opti-push` after or concurrent with `next build` is a silent bug factory: the build's `generateStaticParams` can fetch content whose schema doesn't yet exist in CMS, producing incomplete or empty result sets that get baked into prerendered HTML.

### Which schema changes require `opti-push`

Required (schema needs pushing):
- New content type added
- Property added, renamed, or removed on an existing type
- `displayName` changed on a type or property
- `localized` toggled on a property
- `defaultValue` changed on a property

Not required (purely runtime/React concerns):
- React component JSX edits
- CSS / Tailwind class changes
- `data-epi-edit` attribute changes (these are runtime-only)
- Adding a new display template registration (runtime registry only)

If unsure, run `opti-push` — it's idempotent when nothing has changed.

## Directory layout expected by every pattern in this skill

```
app/
  layout.tsx                    — imports init side-effect
  [locale]/
    layout.tsx                  — HTML shell + Header/Footer
    page.tsx                    — '/{locale}/'
    [...slug]/page.tsx          — everything else
  api/revalidate/route.ts       — POST webhook
  preview/
    layout.tsx
    page.tsx

components/
  optimizely/
    block/ page/ experience/ section/
  layout/
  ui/                           — optional shadcn/ui

lib/
  optimizely/
    init.ts
    content-types.ts
    all-pages.ts
    language.ts
  cache/cache-keys.ts
  image/loader.ts
  metadata.ts
  utils.ts

proxy.ts                        — middleware (see locale-routing.md)
optimizely.config.mjs
next.config.ts
```

The `components/optimizely/` subtree is what the CLI scans via the `components` glob in `optimizely.config.mjs`. Co-locate schema export + default-export React component in the same `.tsx` — the CLI pulls the schema; Next.js pulls the component.

## Post-install checklist

1. Fill `.env.local` with all seven variables.
2. Register at least one content type in `lib/optimizely/init.ts` (including `BlankExperienceContentType` if using Visual Builder).
3. `npm run opti-push` — seeds the CMS with your types.
4. Configure the CMS webhook: `POST https://<your-domain>/api/revalidate?cg_webhook_secret=<value>`.
5. Confirm the CMS Site URL points at your deployed domain (for the preview communication injector to target the correct host).
