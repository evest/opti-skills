---
name: ocp-source-app
description: "Build an Optimizely Connect Platform (OCP) source app from scratch — a Node/TypeScript app that pulls data from an external system (a CRM, OMS, PIM, e-commerce backend, any REST/GraphQL API) and emits it into OCP's data sync pipeline, where it can be routed to Optimizely Graph and consumed by Optimizely SaaS CMS as external content. Use when the user wants to create, scaffold, or extend an OCP 'source' / 'data sync source' app: defining a source schema (app.yml + sources/schema YAML with nested custom types), writing an API client with token auth and paging, building a full-import job and a scheduled incremental sync job (prepare/perform pattern, Quartz cron), wiring the Lifecycle (credential validation, trigger-import button) and the settings form, calling sources.emit(), handling deletes with _isDeleted, and validating/deploying with the ocp CLI and ocp-app-sdk. Covers the @zaiusinc/app-sdk source/job/lifecycle APIs. Do NOT use for OCP destinations only, OCP campaign/channel apps, the CMS content-type SDK, or Optimizely Graph schema authoring on the CMS side."
---

# Building an OCP Source App

How to go from nothing to a working **Optimizely Connect Platform (OCP) source app** — a small Node/TypeScript app that pulls records from an external system and feeds them into OCP's data sync pipeline.

This skill is grounded in two reference implementations (a Shopify product catalog source and an OMS product source) and the official OCP docs. It is **system-agnostic**: the external system can be any CRM, OMS, PIM, or e-commerce backend with a REST or GraphQL API. Examples below use a placeholder system called **Acme**.

## What a source app is (30-second mental model)

```
  External system          OCP source app (this)              OCP Sync Manager           Optimizely Graph / CMS
  ---------------          ---------------------              ----------------           ----------------------
  Records  ── pull ──►  Job: full import (one-off)   ──┐
            (paged)                                      │
                                                         ├─ sources.emit('Thing', {data}) ─► destination ─► Graph ─► SaaS CMS
  Records  ── pull ──►  Job: incremental (scheduled) ──┘                                                    (external content)
            (modified-since)
  Records  ── push ──►  Function: webhook (optional, real-time)
```

The app **only produces records.** It declares one or more **sources** (typed schemas) and calls `sources.emit('<Source>', { data })`. Routing those records onward to a destination (e.g. Optimizely Graph) is a one-time configuration on the OCP tracker, not something the app code does.

There are two ways to get data in, and most apps use the pull model:

- **Pull (jobs)** — the dominant pattern. A **full-import job** backfills everything once; a **scheduled job** picks up changes on a cron. Works against any API, needs no inbound connectivity. This skill leads with this model.
- **Push (functions)** — a **webhook function** receives real-time events from the external system. Only viable if the system can call out to a webhook. Covered as an option in `references/lifecycle-and-forms.md`.

## Prerequisites

- Node.js 22+ and a package manager (the reference apps use yarn; npm works too).
- The **OCP CLI** installed and authenticated, plus a tracker ID to install against. Quick path (full setup in `references/deployment.md`): install via `curl -fsSL https://cli.ocp.optimizely.com/install.sh | bash` (macOS/Linux) or `iwr -useb https://cli.ocp.optimizely.com/install.ps1 | iex` (Windows PowerShell); put `{"apiKey": "<from-invitation>"}` in `~/.ocp/credentials.json`; verify with `ocp accounts whoami`. See [Configure your development environment](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/configure-your-development-environment-ocp2).
- Credentials/API access for the external system you're syncing from.

Key official docs:
- [Developer platform overview](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/developer-platform-overview-ocp2)
- [Build an app](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/build-an-app-ocp2)
- [Source](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/source) · [Custom data sync destinations](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/custom-data-sync-destinations)
- [app.yml structure](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/app-structure-appyml-ocp2) · [Schedule jobs with cron](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/schedule-jobs-using-cron-expressions-ocp2)
- [Local testing](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/local-testing)

## The build, end to end

The recommended order. Each step is small and verifiable; run `yarn validate` often.

1. **Scaffold** the project (config files + `app.yml` + `forms/` + `assets/`).
2. **Define the source schema** — the typed shape of a record (`src/sources/schema/<name>.yml`).
3. **Write the API client** — token auth, paging, single-record fetch, typed responses.
4. **Write the transform** — a pure function mapping an external record to the source-schema payload.
5. **Write the full-import job** — paged backfill, emits every record.
6. **Write the incremental sync job** (or a webhook function) — picks up changes.
7. **Wire the Lifecycle + settings form** — validate credentials, trigger imports, clean up on uninstall.
8. **Test** — unit-test the client (mocked fetch) and the transform (pure function).
9. **Validate** — `yarn validate` (build + lint + test + `ocp-app-sdk validate`).
10. **Deploy** — `ocp app prepare --publish` then `ocp directory install`, then connect the source to a destination in the tracker UI.

Detailed, copy-pasteable patterns live in the reference files:

| Reference | Covers |
| --- | --- |
| `references/source-schema.md` | Schema YAML: field types, nested custom types, primary key, deletes, dynamic schemas |
| `references/api-client.md` | Token auth + caching, paging/scrolling, retries, typed responses, mocked-fetch tests |
| `references/jobs-and-sync.md` | Full-import job, scheduled incremental job, cron, cursors, resume, retries |
| `references/lifecycle-and-forms.md` | Settings form, Lifecycle methods, credential validation, trigger button, webhook option |
| `references/testing-and-troubleshooting.md` | Vitest setup, common `validate` failures, gotchas |
| `references/deployment.md` | OCP CLI install/auth, publish/install loop, connecting the source to a destination, ops commands |

---

## Step 1 — Scaffold

Target layout (mirrors both reference apps):

```
my-source-app/
├── app.yml                              OCP manifest: meta, runtime, sources, jobs (+ functions if webhook)
├── package.json                         scripts: build / test / lint / validate
├── tsconfig.json
├── eslint.config.mjs
├── vitest.config.ts
├── forms/settings.yml                   settings UI (credentials, options, trigger button)
├── assets/
│   ├── icon.svg
│   ├── logo.svg
│   └── directory/overview.md
└── src/
    ├── sources/schema/thing.yml         the source schema
    ├── data/AcmeTypes.ts                external-system TypeScript interfaces
    ├── lib/
    │   ├── AcmeClient.ts                API client
    │   └── transformToPayload.ts        external record → schema payload
    ├── jobs/
    │   ├── ImportThings.ts              full import
    │   └── IncrementalSync.ts           scheduled delta (or functions/ThingWebhook.ts)
    └── lifecycle/Lifecycle.ts           credential validation + import trigger + uninstall
```

### `package.json`

```json
{
  "name": "acme_source_app",
  "version": "1.0.0-dev.1",
  "main": "dist/index.js",
  "license": "UNLICENSED",
  "scripts": {
    "build": "rimraf dist && tsc && cpy app.yml dist && cpy --up 1 \"src/**/*.{yml,yaml}\" dist",
    "validate": "rimraf dist && tsc && cpy app.yml dist && cpy --up 1 \"src/**/*.{yml,yaml}\" dist && npx eslint src --ext ts && cross-env LOG_LEVEL=NEVER ocp-app-sdk validate",
    "lint": "npx eslint src --ext ts",
    "test": "vitest run --passWithNoTests"
  },
  "devDependencies": {
    "@types/node": "^22.15.17",
    "@zaiusinc/eslint-config-presets": "^3.1.0",
    "cpy-cli": "^6.0.0",
    "cross-env": "^7.0.3",
    "dotenv": "^16.5.0",
    "rimraf": "^6.0.1",
    "typescript": "^5.8.3",
    "vitest": "^4.0.8"
  },
  "dependencies": {
    "@zaiusinc/app-sdk": "3.3.4",
    "@zaiusinc/node-sdk": "3.0.0"
  }
}
```

> The build copies `app.yml` and every `src/**/*.yml` into `dist/` because `ocp-app-sdk validate` and the OCP runtime read the **compiled** `dist/` tree. Forgetting the YAML copy is the most common "validation can't find my schema" cause.

> **`validate` deliberately does *not* chain `vitest run`.** `ocp app prepare` invokes the `validate` script, so keeping it to build + lint + `ocp-app-sdk validate` keeps publish fast and avoids coupling the test runner to the publish path. Keep tests in a separate `yarn test` step and run both before deploying.

### `tsconfig.json`

Strict, CommonJS or NodeNext, `experimentalDecorators` on (jobs/functions are decorated classes), `noEmitOnError` so type errors block the build:

```json
{
  "include": ["./src"],
  "exclude": ["node_modules", "dist"],
  "compilerOptions": {
    "rootDir": "./src",
    "outDir": "./dist",
    "declaration": true,
    "moduleResolution": "node",
    "lib": ["es2018"],
    "module": "commonjs",
    "target": "es2018",
    "sourceMap": true,
    "experimentalDecorators": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "noEmitOnError": true,
    "strict": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true
  }
}
```

### `eslint.config.mjs` and `vitest.config.ts`

```js
// eslint.config.mjs
import node from '@zaiusinc/eslint-config-presets/node.mjs';
import vitest from '@zaiusinc/eslint-config-presets/vitest.mjs';

export default [
  ...node,
  ...vitest,
  { files: ['**/*.test.ts'], rules: { '@typescript-eslint/unbound-method': 'off' } },
];
```

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import dotenv from 'dotenv';

dotenv.config({ path: '.env.test' });
process.env.ZAIUS_ENV = 'test';   // makes storage.* use in-memory local stores

export default defineConfig({
  test: { environment: 'node', include: ['src/**/*.test.ts'], globals: true },
});
```

Add a `.env.test` with `LOG_LEVEL=NEVER` to silence SDK logs during tests.

### `app.yml`

The manifest. `app_id` is lowercase snake_case and unique; `version` is semver with a `-dev.N` suffix while iterating; `runtime` is `node22`. Declare one source and the jobs:

```yaml
meta:
  app_id: acme_source
  display_name: Acme Source
  version: 1.0.0-dev.1
  vendor: your-company
  summary: Sync records from Acme into Optimizely Connect Platform
  support_url: https://support.example.com
  contact_email: support@example.com
  categories:
    - Commerce Platform        # see app.yml docs for the full category list
  availability:
    - all                      # us | eu | au | all

runtime: node22

sources:
  Thing:                       # the KEY here is the source name you pass to sources.emit()
    description: Acme Thing
    schema: thing               # filename (without .yml) under src/sources/schema/

jobs:
  import_things:
    entry_point: ImportThings   # must match the exported class name in src/jobs/
    description: One-time full import of all Acme things
  incremental_sync:
    entry_point: IncrementalSync
    description: Scheduled incremental sync of things modified since the last run
    cron: '0 0 0/1 * * ?'       # Quartz 6-field — see jobs-and-sync.md. Hourly at :00.
```

> **Source name casing:** the key under `sources:` (`Thing`) is exactly the string you pass to `sources.emit('Thing', …)`. Keep them in sync.

> **Cron is Quartz 6-field** (`seconds minutes hours day-of-month month day-of-week`), **not** standard 5-field Unix cron. `0 * * * *` is rejected by `ocp-app-sdk validate`. Use `0 0 0/1 * * ?` for hourly. Details and a table in `references/jobs-and-sync.md`.

### `forms/settings.yml` and `assets/`

The settings form drives the in-tracker UI (credentials, sync options, a trigger-import button). Full structure in `references/lifecycle-and-forms.md`. Provide `assets/icon.svg`, `assets/logo.svg`, and `assets/directory/overview.md` (a short marketing-style description shown in the App Directory).

---

## Steps 2–7 — the core files (at a glance)

Each of these has a dedicated reference with full code. The summaries below give you the shape.

### Source schema (`references/source-schema.md`)

A YAML file declaring the record's typed fields and any nested object types. One field is the `primary: true` key. Supported types: `string`, `integer`/`int`, `long`, `float`/`decimal`, `boolean`, arrays like `[string]`, and named custom types / arrays of them (`[variant]`). Example skeleton:

```yaml
name: thing
display_name: Things
description: Acme things with nested children
fields:
  - name: thing_id
    type: string
    display_name: Thing ID
    primary: true
  - name: title
    type: string
    display_name: Title
  - name: children
    type: "[child]"
    display_name: Children
custom_types:
  - name: child
    display_name: Child
    fields:
      - name: child_id
        type: string
        display_name: Child ID
```

### API client (`references/api-client.md`)

A class that owns all HTTP to the external system: acquires/caches an auth token (persisted in `storage.kvStore`, refreshed before expiry, retried once on 401), exposes paged listing + single-record fetch, and returns typed responses. Keep all `fetch` here so token + retry logic stays in one place.

### Transform (`references/source-schema.md`)

A **pure function** `externalRecord → payload` matching the schema. No SDK calls — that keeps it trivially testable. Normalize quirks here (sentinel dates → `null`, empty strings → `null`, missing booleans → `false`).

### Jobs (`references/jobs-and-sync.md`)

- **Full import**: `prepare` builds the client and initial state; `perform` fetches one page, emits each transformed record via `sources.emit('Thing', { data })`, advances the cursor, and sets `complete: true` when the source is exhausted. Retries with backoff. On completion, seed the incremental cursor.
- **Incremental sync**: scheduled via `cron`. Reads a stored "modified since" cursor from `storage.kvStore`, queries the modified window, emits, and only advances the cursor after the window completes successfully (so a crash re-runs the window rather than skipping it). Emits are idempotent upserts keyed by the primary key.

### Lifecycle + forms (`references/lifecycle-and-forms.md`)

`Lifecycle.onSettingsForm` validates credentials (by making a real auth call) before saving them, and handles the trigger-import button via `jobs.trigger('import_things', {})`. `onUninstall` clears cached tokens/cursors. If using webhooks instead of scheduled sync, this is also where you register/deregister them.

---

## Step 8 — Test

Two high-value unit suites, no live API needed:

- **Client** — mock `global.fetch`; assert token caching, the 401-refresh path, request URLs/bodies, and error propagation.
- **Transform** — pure input→output assertions, including edge cases (empty record, sentinel values, missing arrays).

Use `resetLocalStores()` from `@zaiusinc/app-sdk` in `afterEach`, and `vi.mock('@zaiusinc/app-sdk', …)` to stub `sources.emit`. Patterns in `references/testing-and-troubleshooting.md`.

## Step 9 — Validate

```bash
yarn validate     # build + lint + vitest + ocp-app-sdk validate
```

`ocp-app-sdk validate` parses `dist/app.yml`, checks every job/function `entry_point` resolves to a class with the right methods, checks schema references, and rejects invalid CRON. If it can't find your schema or entry point, you almost certainly forgot to `build` (copy YAML into `dist/`) or mismatched a name. See the failure table in `references/testing-and-troubleshooting.md`.

## Step 10 — Deploy and connect

```bash
ocp app prepare --publish
ocp directory install acme_source@1.0.0-dev.1 <TRACKER_ID>
```

Then in the OCP tracker UI:
1. Open the app settings; enter and save credentials (the app validates them).
2. In Data Sync, create/choose a **destination** (e.g. Optimizely Graph) and map the `Thing` source to it. See [custom data sync destinations](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/custom-data-sync-destinations).
3. Click the **Run Full Import** button to backfill.
4. The scheduled `incremental_sync` job keeps it current.

Bump `meta.version` (`-dev.2`, `-dev.3`, …) on every republish — published versions are immutable. Full CLI setup, the publish/install loop, dev-vs-release versions, and ops commands (`ocp jobs trigger`, `ocp app logs`, `ocp directory list-installs`) are in `references/deployment.md`.

---

## Decisions to make up front

When a user asks for a source app, resolve these before writing code — they shape the schema and the job loop. If the user hasn't said, ask (or pick the recommended default and note it):

| Decision | Options | Default |
| --- | --- | --- |
| **Sync strategy** | scheduled incremental + manual full import · real-time webhooks · full-import-only | scheduled incremental + manual full import (works without inbound connectivity) |
| **Record granularity** | nested children under a parent · separate sources per entity · both | nest children under the parent (one emit per parent) |
| **Multi-variant / multi-locale data** | one record per variant/locale · one record with nested/localized fields | depends on how the destination/Graph consumer wants to query — confirm with the user |
| **Auth model** | static API token (header) · OAuth client-credentials token endpoint · OAuth interactive | match the external system; client-credentials/token-endpoint is most common for server-to-server |
| **Delete handling** | emit `_isDeleted: true` on delete events · ignore (let records go stale) | emit deletes if the source can detect them |

## Cross-cutting conventions (from the reference apps)

- **All HTTP goes through the client class** — never `fetch` directly from a job/lifecycle, so token caching + retry stay consistent.
- **Transforms are pure** — no SDK calls inside the transform; makes them trivially testable.
- **State stored in `kvStore` must extend `KVHash`/`ValueHash`** (it has an index signature). `JobStatus.state` likewise must be a `ValueHash`. This is the #1 TypeScript friction point — see `references/jobs-and-sync.md`.
- **`kvStore` keys are flat strings**, e.g. `acme_token:<clientId>`, `acme_sync:cursor`. There is no namespace argument.
- **Emit is an upsert** keyed by the primary key; re-emitting the same record is safe. This is what makes incremental retries safe.
- **Guarantee Graph's required metadata.** Every item synced to Optimizely Graph needs a non-empty `displayName` and a `lastModified`. Make the source field you'll map to `displayName` never empty (fall back to the primary key), and synthesize a `lastModified` (the job's run time) when the external record has none. Missing values fail the sync with `REQUIRED_FIELD_MISSING` even though `validate` passes — see `references/source-schema.md`.
- **Removing the OCP data sync does NOT clear Graph.** The Graph content source (schema + data) persists when you delete/disable the sync or uninstall the app — a stale schema there can `500` the CMS Content Manager when the source is selected. Clear it via the Graph REST API (`DELETE /api/content/v3/sources?id=<source>`), then re-import. See `references/deployment.md`.
- **Keep `perform` work units < 60s** and checkpoint state each iteration; the runtime can evict a long-running job. Use `this.sleep(ms, { interruptible: true })` for long waits.
- **Notify on terminal outcomes** via `notifications.success` / `notifications.error` so operators see import results in the tracker.
- **External-system credentials come from the settings form, not env vars.** The app reads them at runtime via `storage.settings.get(...)`, so `app.yml`'s `environment:` is usually empty. `ocp app prepare` scans `.env`/`.env.<env>`/`.env.<shard>`, requires every var there to be declared in `environment:`, and registers declared values with the app version — so there's no reason to list settings-form credentials there. Keep local-only script values (diagnostics, REST snippets) in `.env.diagnostics` (ignored by the publish scan, still git-ignored via `.env.*`). See `references/deployment.md`.
