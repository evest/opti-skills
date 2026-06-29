# Deployment

Getting the app from your machine onto an OCP tracker, where it can run jobs and feed a destination. Two phases: a **one-time CLI setup**, then the **per-release publish/install loop**.

Authoritative docs: [Configure your development environment](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/configure-your-development-environment-ocp2) and [Build an app](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/build-an-app-ocp2).

## One-time: install & authenticate the OCP CLI

### Install

**macOS / Linux:**
```bash
curl -fsSL https://cli.ocp.optimizely.com/install.sh | bash
```

**Windows (PowerShell):**
```powershell
iwr -useb https://cli.ocp.optimizely.com/install.ps1 | iex
```

**Or via npm (no global install):**
```bash
npx @optimizely/ocp-cli-v2 <command>     # substitute for `ocp` below
```

### Authenticate

The CLI reads an API key from `~/.ocp/credentials.json`. The key comes from your OCP onboarding/invitation email.

```bash
mkdir -p ~/.ocp
# credentials.json:  {"apiKey": "<value-from-invitation>"}
```

PowerShell equivalent for creating the file:
```powershell
mkdir ~/.ocp -Force
'{"apiKey": "<value-from-invitation>"}' | Out-File ~/.ocp/credentials.json -Encoding utf8
```

### Verify

```bash
ocp accounts whoami
```

Returns your account ID, email, role, and the accounts/trackers you can reach. If this fails, fix it before going further — every command below depends on it. The **tracker ID** you install against comes from your account (an account/tracker you can see in `whoami` or the OCP UI).

## Per-release: validate → publish → install

### 1. Validate locally first

```bash
yarn validate     # build + lint + test + ocp-app-sdk validate
```

Never publish without this passing — `ocp app prepare` runs its own validation server-side and will reject the same problems, but locally is faster. See `testing-and-troubleshooting.md` for the common failure table.

### 2. Prepare (and publish) the build

```bash
ocp app prepare --publish
```

`ocp app prepare` validates, packages, uploads, and builds the app from the current directory. The `--publish` flag also publishes the resulting version so it's installable. (You can instead split the steps: `ocp app prepare` then `ocp directory publish <appId@appVersion>`.)

The published identifier is `<app_id>@<version>` from `app.yml`'s `meta` — e.g. `acme_source@1.0.0-dev.1`. **Bump `meta.version`** (`-dev.2`, `-dev.3`, …) for every republish; you can't overwrite an existing published version.

#### How `ocp app prepare` handles `.env` files — keep local-only values in a separate file

`ocp app prepare` reads your `.env` files and **validates them against `app.yml`** before packaging, then registers the matched values with the app version. Because of this, keep any value you only use locally (e.g. for a diagnostics script) in a separate file rather than `.env`. The behavior (from the CLI's `gatherAppEnv`):

- In the `production` environment it scans **`.env`**, **`.env.<env>`** (e.g. `.env.production`), and per-shard **`.env.<shard>`** (e.g. `.env.us`).
- Validation is **bidirectional**:
  - Any variable in those files **not** declared in `app.yml`'s top-level `environment:` array → error: *"One of the env files contains a variable not listed in the app.yml: `VAR`"*.
  - Any variable **declared** in `environment:` with no value in those files → error: *"None of the env files provide a value for the required variable: `VAR`"*.
- The matched values are then **registered with the app version** in OCP (per shard), so they're available to the running app via `process.env`. Declaring a var in `environment:` is what makes its value part of the deployed app.
- `meta.availability: all` **forbids** shard-specific `.env.<shard>` files.

`environment:` is for variables your **app runtime** actually reads via `process.env`. Declare those, and provide their values in the appropriate `.env*` file:

```yaml
# app.yml — only for vars the running app reads via process.env
environment:
  - SOME_RUNTIME_FLAG
```

> **Source apps usually need an empty `environment:`.** A source app receives external-system credentials at runtime from the **settings form** (`storage.settings.get('acme_credentials')`), not from `process.env`. So those credentials should *not* be in `app.yml` `environment:` and should *not* live in `.env`.

**Local-only credentials (diagnostics scripts, REST snippets) belong in `.env.diagnostics`, not `.env`.** The publish scan only reads `.env` / `.env.<env>` / `.env.<shard>` — a differently-named file like `.env.diagnostics` is ignored by it, while still being git-ignored (it matches `.env.*`) and loadable by your own scripts:

```js
// scripts/acme-diagnostics.js — load the local-only file, fall back to .env
require('dotenv').config({ path: '.env.diagnostics' });
require('dotenv').config({ path: '.env' });
```

Since a source app reads external-system credentials from the settings form rather than `process.env`, there's no reason to add them to `environment:` — keep such local-only values in `.env.diagnostics` instead, where the publish scan won't pick them up.

### 3. Install onto a tracker

```bash
ocp directory install acme_source@1.0.0-dev.1 <TRACKER_ID>
```

To see existing installs of a version (and confirm the install landed):

```bash
ocp directory list-installs acme_source@1.0.0-dev.1
```

### 4. Configure and run, in the tracker UI

1. Open the app's settings; enter and **save credentials** (the Lifecycle validates them with a real auth call).
2. In **Data Sync**, create or choose a **destination** (e.g. Optimizely Graph) and **map the `Thing` source** to it. The app only emits records; this mapping is what routes them onward. When the destination is Graph, also map a non-empty field to **`displayName`** and a timestamp field to **`lastModified`** — both are required (see `references/source-schema.md`). See [custom data sync destinations](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/custom-data-sync-destinations).
3. Click **Run Full Import** to backfill.
4. Confirm the scheduled `incremental_sync` job is running on its cron.

## Useful operational commands

```bash
# Trigger a job manually (e.g. re-run the import without the UI button)
ocp jobs trigger acme_source@1.0.0-dev.1 import_things <TRACKER_ID>

# Tail app logs (job runs, emits, errors, notifications)
ocp app logs acme_source

# List installs of a version
ocp directory list-installs acme_source@1.0.0-dev.1
```

> Command surface differs slightly between CLI versions. If a subcommand name doesn't resolve, run `ocp --help` or `ocp <group> --help` (e.g. `ocp directory --help`) to see the exact form your CLI exposes.

## Managing & clearing the Graph content source

When the destination is Optimizely Graph, your emitted records land in a **Graph content source** — a store separate from OCP, addressed by a short source id (≤4 chars, lowercase `a–z`/`0–9`). Graph exposes a REST API to inspect and clear it, which you need when a schema change leaves the source in a bad state.

> **The big gotcha: removing the data sync in OCP does NOT clear the Graph source.** Deleting/disabling the data-sync mapping — or even uninstalling the app — stops *new* emits but leaves the already-synced **schema and data in Graph untouched**. A stale or conflicting schema lingers there and commonly surfaces as a **`500` error in the CMS Content Manager when you select that source as a content source**. To actually reset it you must call the Graph REST API directly, then re-import.

Base URL `https://cg.optimizely.com` (override per region if needed). Auth is **Basic** (`username = AppKey`, `password = Secret`) or `epi-hmac`. These credentials belong to the **CMS/Graph instance, not OCP** — get them from the CMS's Graph configuration, and keep them in `.env.diagnostics`, never `.env` (same publish-scan reason as app credentials, above).

```bash
# List sources — find the id
curl -u "$APPKEY:$SECRET" "https://cg.optimizely.com/api/content/v3/sources"

# Inspect the registered content types / schema for a source (read-only)
curl -u "$APPKEY:$SECRET" "https://cg.optimizely.com/api/content/v3/types?id=<source>"

# Clear a source.  mode: (omitted)=types+data · types · data · reset
curl -u "$APPKEY:$SECRET" -X DELETE "https://cg.optimizely.com/api/content/v3/sources?id=<source>"

# Purge data only (keep the schema), optionally per language
curl -u "$APPKEY:$SECRET" -X DELETE "https://cg.optimizely.com/api/content/v2/data?id=<source>&languages=en"
```

- **Corrupted schema** (field type drifted across republishes, CMS 500): delete with no `mode` (drops types + data), then re-run a full import so the source re-registers cleanly. Inspect with the `types` call first to see what drifted.
- **Stale data only**: use `mode=data` or the `v2/data` purge — the schema stays.
- **Target the specific source id.** An empty `id` deletes *all* sources, and `default` is usually the CMS instance's own content source — deleting it wipes CMS content, not yours. Confirm the id with the list/types calls before any DELETE.

After clearing, trigger a **full import** so OCP re-pushes the schema and data.

## dev vs. published versions

- A `-dev.N` suffix marks a **development version** — fine for installing onto your own tracker during iteration.
- For a real release (and App Directory listing/approval), drop the suffix and publish a clean semver (`1.0.0`). Approval/availability is governed by `meta.availability` and the OCP directory review process.

## Deployment troubleshooting

| Symptom | Check |
| --- | --- |
| `ocp accounts whoami` fails | `~/.ocp/credentials.json` exists with a valid `apiKey`; key not expired/rotated. |
| `prepare` rejects the app | Same checks as local `ocp-app-sdk validate` — see the failure table in `testing-and-troubleshooting.md`. |
| "version already exists" on publish | Bump `meta.version` in `app.yml`; published versions are immutable. |
| `prepare`: "env files contains a variable not listed in the app.yml: `VAR`" | A `.env`/`.env.<env>`/`.env.<shard>` file has a var not in `app.yml` `environment:`. If the app reads it via `process.env`, declare it; if it's a local-only script credential, move it to `.env.diagnostics` (see the publish section above). |
| `prepare`: "None of the env files provide a value for the required variable: `VAR`" | `environment:` declares `VAR` but no `.env*` file supplies a value. Provide it, or remove `VAR` from `environment:` if the app doesn't actually read it. |
| Install succeeds but no data flows | The `Thing` source must be **mapped to a destination** in the tracker; emitting alone does nothing. |
| Sync fails with `REQUIRED_FIELD_MISSING: displayName` / `lastModified` | A record's mapped metadata field is empty. Map a guaranteed-non-empty field to `displayName` and a timestamp to `lastModified`, and make the source always populate them (fall back to the primary key / stamp the run time). See `references/source-schema.md`. |
| Job never runs | Confirm the install is active (`list-installs`), credentials saved, and (for scheduled) the cron is valid Quartz. Check `ocp app logs`. |
| CMS **Content Manager returns `500`** when selecting the source | Stale/corrupted schema in the Graph content source. Removing the OCP data sync does **not** clear it — clear the Graph source via the Delete source API, then re-import. See "Managing & clearing the Graph content source". |
| Removed/changed the data sync but old data or schema is still in Graph | OCP does **not** cascade-delete the Graph source when you remove the sync. Clear it explicitly via the Graph REST API (`DELETE /api/content/v3/sources?id=<source>`). |
