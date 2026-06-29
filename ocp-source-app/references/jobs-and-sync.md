# Jobs & sync strategy

Jobs are the pull engine of a source app. Each is a class extending `Job` from `@zaiusinc/app-sdk`, referenced from `app.yml` by `entry_point` (the class name). Two jobs cover most needs:

- **Full import** — manually triggered, backfills everything once.
- **Incremental sync** — scheduled on a cron, picks up changes since the last run.

## The Job model

```ts
abstract prepare(params: ValueHash, status?: JobStatus, resuming?: boolean): Promise<JobStatus>;
abstract perform(status: JobStatus): Promise<JobStatus>;
```

- `prepare` runs once at start (and again on resume). Read settings, build the client, compute the initial state.
- `perform` runs in a **loop**. Each call does a **small unit of work (< 60s)**, returns the updated `JobStatus`. The runtime calls `perform` again with the returned status until `complete: true`.
- `JobStatus` is `{ state: ValueHash; complete: boolean }`. The `state` is your checkpoint — store the cursor, counts, and a retry counter there. If a job is evicted, it resumes by calling `prepare(params, lastStatus)` then looping `perform` from the saved state.

> **TypeScript gotcha:** `JobStatus.state` must be a `ValueHash` (it has a string index signature). Declare your state interface as `interface MyState extends ValueHash { … }`, otherwise `tsc` rejects it with "missing index signature". Same rule for anything written to `storage.kvStore` (extend `KVHash`).

## Full-import job

Pattern: page through the whole catalog, emit each transformed record, checkpoint the cursor each iteration, finish when the source is exhausted, and **seed the incremental cursor** so the next scheduled run starts cleanly.

```ts
import {
  Job, JobStatus, logger, notifications, sources, storage, ValueHash,
} from '@zaiusinc/app-sdk';
import { AcmeClient } from '../lib/AcmeClient';
import { transformToPayload } from '../lib/transformToPayload';

const DEFAULT_BATCH = 50;
const MAX_RETRIES = 5;
const CURSOR_KEY = 'acme_sync:cursor';

interface ImportState extends ValueHash {
  cursor: string | null;
  processed: number;
  retries: number;
  startedAt: string;
}
interface ImportStatus extends JobStatus { state: ImportState; }

export class ImportThings extends Job {
  private client!: AcmeClient;
  private batch = DEFAULT_BATCH;

  public async prepare(_params: ValueHash, status?: ImportStatus): Promise<ImportStatus> {
    const creds: Record<string, string> = await storage.settings.get('acme_credentials');
    const opts: Record<string, string | number> = await storage.settings.get('sync_options');

    if (!creds.api_url || !creds.client_id || !creds.client_secret) {
      await notifications.error('Acme Sync', 'Import Failed', 'Credentials are not configured.');
      return { state: emptyState(), complete: true };
    }

    this.client = new AcmeClient({
      apiUrl: creds.api_url, clientId: creds.client_id, clientSecret: creds.client_secret,
    });
    const n = Number(opts?.batch_size);
    this.batch = Number.isFinite(n) && n > 0 ? Math.min(n, 500) : DEFAULT_BATCH;

    return status ?? { state: emptyState(), complete: false };
  }

  public async perform(status: ImportStatus): Promise<ImportStatus> {
    const s = status.state;
    try {
      const result = await this.client.listThings(s.cursor ?? undefined, this.batch);
      for (const thing of result.items) {
        await sources.emit('Thing', { data: transformToPayload(thing) as any });
      }
      s.processed += result.items.length;
      s.cursor = result.nextCursor ?? null;
      s.retries = 0;
      logger.info(`Imported ${s.processed} things so far`);

      if (!s.cursor || result.items.length === 0) {
        // Seed the incremental cursor to this job's start time so the next scheduled run continues cleanly.
        await storage.kvStore.put(CURSOR_KEY, { modifiedFrom: s.startedAt });
        await notifications.success('Acme Sync', 'Import Complete', `Imported ${s.processed} things.`);
        status.complete = true;
      }
      return status;
    } catch (err: any) {
      logger.error(`Import error: ${err.message}`);
      if (s.retries >= MAX_RETRIES) {
        await notifications.error('Acme Sync', 'Import Failed', `${err.message}. Max retries exceeded.`);
        status.complete = true;
      } else {
        s.retries++;
        await new Promise((r) => setTimeout(r, s.retries * 5000)); // linear backoff
      }
      return status;
    }
  }
}

function emptyState(): ImportState {
  return { cursor: null, processed: 0, retries: 0, startedAt: new Date().toISOString() };
}
```

## Incremental sync job (scheduled)

Scheduled with a `cron` in `app.yml`. Reads a stored "modified since" cursor, queries the modified window, emits, and **advances the cursor only after the whole window completes** — so a crash re-runs the window instead of skipping changes. Re-emitting is safe (emit is an upsert).

```ts
import {
  Job, JobStatus, KVHash, logger, notifications, sources, storage, ValueHash,
} from '@zaiusinc/app-sdk';
import { AcmeClient } from '../lib/AcmeClient';
import { transformToPayload } from '../lib/transformToPayload';

const DEFAULT_BATCH = 50;
const DEFAULT_LOOKBACK_MIN = 120;
const MAX_RETRIES = 3;
const CURSOR_KEY = 'acme_sync:cursor';

interface SyncState extends ValueHash {
  modifiedFrom: string; modifiedTo: string;
  page: number; processed: number; retries: number;
}
interface SyncStatus extends JobStatus { state: SyncState; }
interface Cursor extends KVHash { modifiedFrom?: string; }

export class IncrementalSync extends Job {
  private client!: AcmeClient;
  private batch = DEFAULT_BATCH;

  public async prepare(_params: ValueHash, status?: SyncStatus): Promise<SyncStatus> {
    const creds: Record<string, string> = await storage.settings.get('acme_credentials');
    const opts: Record<string, string | number> = await storage.settings.get('sync_options');
    if (!creds.api_url || !creds.client_id || !creds.client_secret) {
      logger.warn('Skipping incremental sync: credentials not configured');
      return { state: emptyState(), complete: true };
    }
    this.client = new AcmeClient({
      apiUrl: creds.api_url, clientId: creds.client_id, clientSecret: creds.client_secret,
    });
    const n = Number(opts?.batch_size);
    this.batch = Number.isFinite(n) && n > 0 ? Math.min(n, 500) : DEFAULT_BATCH;

    if (status) return status; // resuming

    const lookback = Number(opts?.incremental_lookback_minutes);
    const fallbackMin = Number.isFinite(lookback) && lookback > 0 ? lookback : DEFAULT_LOOKBACK_MIN;
    const cursor = await storage.kvStore.get<Cursor>(CURSOR_KEY);
    const now = new Date();
    const modifiedTo = now.toISOString();
    const modifiedFrom = cursor?.modifiedFrom ?? new Date(now.getTime() - fallbackMin * 60_000).toISOString();

    return { state: { modifiedFrom, modifiedTo, page: 0, processed: 0, retries: 0 }, complete: false };
  }

  public async perform(status: SyncStatus): Promise<SyncStatus> {
    const s = status.state;
    try {
      const result = await this.client.listThingsModifiedSince(s.modifiedFrom, s.modifiedTo, s.page, this.batch);
      for (const thing of result.items) {
        await sources.emit('Thing', { data: transformToPayload(thing) as any });
      }
      s.processed += result.items.length;
      s.page += 1;
      s.retries = 0;

      const done = result.items.length === 0 || result.items.length < this.batch || !result.nextCursor;
      if (done) {
        await storage.kvStore.put(CURSOR_KEY, { modifiedFrom: s.modifiedTo }); // advance only on success
        if (s.processed > 0) {
          await notifications.success('Acme Sync', 'Incremental Sync Complete', `Synced ${s.processed} thing(s).`);
        }
        status.complete = true;
      }
      return status;
    } catch (err: any) {
      logger.error(`Incremental sync error: ${err.message}`);
      if (s.retries >= MAX_RETRIES) {
        await notifications.error('Acme Sync', 'Incremental Sync Failed',
          `${err.message}. Cursor not advanced; will retry next schedule.`);
        status.complete = true; // leave cursor where it was
      } else {
        s.retries++;
        await new Promise((r) => setTimeout(r, s.retries * 5000));
      }
      return status;
    }
  }
}

function emptyState(): SyncState {
  const now = new Date().toISOString();
  return { modifiedFrom: now, modifiedTo: now, page: 0, processed: 0, retries: 0 };
}
```

### Why advance the cursor only at the end

If you advanced per-page and the job died mid-window, the changes in the unprocessed pages would be skipped forever. Advancing only after the full window completes means a crash simply re-runs the window — and because emit is an idempotent upsert keyed by the primary key, re-processing is harmless.

## Cron (Quartz 6-field)

OCP uses **Quartz** cron, not Unix 5-field cron. Order: `seconds minutes hours day-of-month month day-of-week`, with `?` allowed in the day-of-month or day-of-week field. A plain `0 * * * *` is **rejected** by `ocp-app-sdk validate`.

| Frequency | Expression |
| --- | --- |
| Every minute | `0 * * ? * *` |
| Every 15 minutes | `0 0/15 * ? * *` |
| Hourly (at :00) | `0 0 0/1 * * ?` |
| Every 12 hours | `0 0 0/12 * * ?` |
| Daily at noon | `0 0 12 * * ?` |
| Daily at midnight | `0 0 0 * * ?` |

```yaml
jobs:
  incremental_sync:
    entry_point: IncrementalSync
    description: Scheduled incremental sync
    cron: '0 0 0/1 * * ?'
```

## Triggering jobs

- **From the settings form button** — `Lifecycle.onSettingsForm` calls `jobs.trigger('import_things', {})` (see `lifecycle-and-forms.md`).
- **From the CLI** — `ocp jobs trigger <app_id@version> import_things <TRACKER_ID>` (see `deployment.md`).
- **From cron** — the scheduled job fires automatically.

## Long waits inside a job

If a `perform` step must wait on a long external operation (e.g. an export the API prepares asynchronously), don't block: set work up so you can checkpoint and use `await this.sleep(ms, { interruptible: true })`, which lets the runtime evict and resume you with the saved state. Keep each non-interruptible stretch under ~55s.

## Where state lives

| State | Key / location | Reset by |
| --- | --- | --- |
| Cached auth token | `kvStore` `acme_token:<clientId>` | uninstall, expiry, 401 |
| Incremental cursor | `kvStore` `acme_sync:cursor` | uninstall, or successful full import |
| Per-run cursor / counts / retries | `JobStatus.state` (ephemeral) | each new run |
| Credentials, sync options | `storage.settings` | uninstall |
