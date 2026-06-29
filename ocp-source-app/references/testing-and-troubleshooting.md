# Testing, validation & troubleshooting

## Test setup

Vitest + the SDK's local-store test mode. `process.env.ZAIUS_ENV = 'test'` (set in `vitest.config.ts`) makes `storage.settings` / `storage.kvStore` use in-memory stores you can read/write directly in tests. Reset them between tests with `resetLocalStores()`.

The two highest-value suites need **no live API**:

1. **Transform** — pure input→output. Cheap, exhaustive, catches mapping regressions.
2. **Client** — `global.fetch` mocked. Asserts token caching, the 401-refresh path, request URLs/bodies, and error handling (see `api-client.md`).

Jobs and the Lifecycle can also be unit-tested by mocking the SDK surface.

### Mocking the SDK in job/lifecycle tests

```ts
import { vi, beforeEach, afterEach, describe, it, expect } from 'vitest';

// Stub the SDK pieces the unit under test calls.
vi.mock('@zaiusinc/app-sdk', async () => {
  const actual = await vi.importActual('@zaiusinc/app-sdk');
  return {
    ...actual,
    sources: { emit: vi.fn() },
    jobs: { trigger: vi.fn() },
    functions: { getEndpoints: vi.fn().mockResolvedValue({ thing_webhook: 'https://example.com/webhook' }) },
  };
});

import { ImportThings } from './ImportThings';
import { resetLocalStores, sources, storage } from '@zaiusinc/app-sdk';

describe('ImportThings', () => {
  let job: ImportThings;
  beforeEach(() => { vi.clearAllMocks(); job = new ImportThings({} as any); });
  afterEach(() => { vi.restoreAllMocks(); resetLocalStores(); });

  it('emits each transformed record', async () => {
    await storage.settings.put('acme_credentials', { api_url: 'x', client_id: 'y', client_secret: 'z' });
    await job.prepare({});
    // ...stub the client's list method, call perform, assert sources.emit was called per item
    expect(sources.emit).toHaveBeenCalledWith('Thing', expect.objectContaining({ data: expect.any(Object) }));
  });
});
```

Tips:
- Construct jobs with `new ImportThings({} as any)` — the constructor wants a `JobInvocation`; tests don't need a real one.
- Mock the **client class** (`vi.mock('../lib/AcmeClient')` or `vi.spyOn(AcmeClient.prototype, 'listThings')`) rather than `fetch`, so job tests focus on the loop logic.
- For retry/backoff tests, use `vi.useFakeTimers()` + `vi.advanceTimersByTime()` so you don't actually wait.
- Seed `storage.settings` in `beforeEach` so `prepare` finds credentials.

## Validation

```bash
yarn build        # tsc + copy app.yml and src/**/*.yml into dist/
yarn validate     # build + eslint + vitest + ocp-app-sdk validate
```

`ocp-app-sdk validate` reads the **compiled** `dist/` tree: it parses `dist/app.yml`, resolves every `entry_point` to a class, checks methods exist, resolves `schema:` references to schema files, and validates CRON.

## Common `validate` / build failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Invalid CRON expression: <Job>` | Used Unix 5-field cron | Use Quartz 6-field, e.g. `0 0 0/1 * * ?` (see jobs-and-sync.md) |
| `Invalid <schema>.yml: fields[N].type 'X' does not match any custom_types name` | Used an unsupported scalar type (commonly `integer`/`int`) — the validator treats any unknown type name as a custom-type reference | Use a supported scalar: `string`, `long`, `float`/`decimal`, `boolean` (or define the custom type). There is **no** `integer` — use `long` for whole numbers. |
| `ENOENT ... dist/app.yml` / schema not found | Ran `validate` without building, or YAML not copied | Run `yarn build` first; ensure the `cpy ... src/**/*.yml dist` step is in your build script |
| `entry point is missing the perform method` | Class name ≠ `entry_point`, or method misnamed | Make the exported class name match `entry_point` exactly; implement `perform` (and `prepare` for jobs) |
| Source emits silently go nowhere | `sources.emit('X')` name ≠ the `sources:` key in app.yml | Match the emit string to the app.yml source key exactly (case-sensitive) |
| `tsc` error "missing index signature" on job state | State/KV interface doesn't extend `ValueHash`/`KVHash` | `interface MyState extends ValueHash { … }` |
| `kvStore.put` type error: expected 1–2 args | Passed a `(namespace, key, value)` triple | `kvStore` keys are flat strings: `kvStore.put('acme_sync:cursor', { … })` |
| Validation can't find a new schema/job | Stale `dist/` | `rimraf dist` is in the build; if you bypassed it, clean and rebuild |
| ESLint `max-len` failures | Lines > 120 chars | Preset caps lines at 120; wrap long template strings |
| `ocp app prepare`: "env files contains a variable not listed in the app.yml" | A `.env`/`.env.<env>`/`.env.<shard>` var isn't declared in `app.yml` `environment:`; `prepare` scans these and registers declared values with the app version | Declare it in `environment:` only if the app reads it via `process.env`; move local-only script values (diagnostics) to `.env.diagnostics`, which the scan ignores. See deployment.md. |

## Runtime troubleshooting (after deploy)

| Symptom | Check |
| --- | --- |
| "Invalid credentials" on save | Is the API URL reachable from OCP egress? Are client ID/secret correct? Try the same call from a local REST client. |
| Import notification never arrives | OCP job logs — look for the error message and the retry counter incrementing. |
| Incremental sync runs but emits nothing | (1) Is the stored cursor already past the change? (2) Is the record's modified timestamp actually after the cursor? (3) Any filter (locale/market/active) excluding it? |
| Token errors after idle | Cache refreshes 5 min before expiry; a 401 triggers one auto-refresh+retry. Persistent 401 = rotated credentials → re-save in the form. |
| Records appear stale / not deleting | Confirm you emit `_isDeleted: true` on delete, and that the destination is mapped to the source. |
| Sync fails: `REQUIRED_FIELD_MISSING: displayName` / `lastModified` | A record's mapped metadata field is empty. Graph requires both on every item. Guarantee them in the source (non-empty `displayName` field, synthesized `lastModified`) and map them in the destination — see `source-schema.md`. |
| CMS Content Manager `500` when selecting the source, or old data/schema lingers after you removed the sync | Stale schema/data in the **Graph content source** — OCP does not clear it when you delete the data sync or uninstall the app. Clear it via the Graph REST API (`DELETE /api/content/v3/sources?id=<source>`) and re-run a full import. See `deployment.md`. |
| First scheduled run scans a huge window | Lower **Incremental Lookback (minutes)** before first run, or run a full import first so the cursor is seeded to the import start time. |

## Pre-flight checklist

- [ ] `app.yml` `app_id` is unique lowercase snake_case; `version` ends in `-dev.N` while iterating.
- [ ] Every `sources:` key matches its `sources.emit('<key>')` call.
- [ ] Every job/function `entry_point` matches its exported class name.
- [ ] Scheduled job uses Quartz 6-field cron.
- [ ] Schema has exactly one `primary: true` field.
- [ ] State/KV interfaces extend `ValueHash` / `KVHash`.
- [ ] `yarn validate` passes clean.
- [ ] After install: credentials validate, source mapped to a destination, full import run, scheduled job confirmed in logs.
