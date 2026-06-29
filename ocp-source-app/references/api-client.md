# The API client

A single class owns all HTTP to the external system. Centralizing it keeps token caching, paging, and retry logic in one testable place — jobs and the lifecycle never call `fetch` directly.

Responsibilities:
- Acquire and **cache an auth token**, refresh it before expiry, retry once on a 401.
- Expose the operations the jobs need: **list/page**, **fetch one**, and a **credential test**.
- Return **typed** responses.

## Two common auth models

### A. Static API token (header)

Simplest — the external system gives a long-lived token that you send as a header. (Shopify-style.) No token endpoint, no caching needed.

```ts
const res = await fetch(url, {
  headers: { 'X-Acme-Access-Token': this.accessToken, 'Content-Type': 'application/json' },
});
```

`testCredentials()` just makes a cheap authenticated GET and returns `response.ok`.

### B. OAuth client-credentials (token endpoint)

Most server-to-server APIs: you exchange a client ID + secret for a short-lived bearer token, then send it as `Authorization: Bearer`. Cache the token (in-memory **and** in `storage.kvStore` so it survives across job iterations / function invocations), refresh before expiry, and retry once on a 401.

```ts
import { KVHash, logger, storage } from '@zaiusinc/app-sdk';
import { AcmeThing, AcmeListResult } from '../data/AcmeTypes';

export interface AcmeCredentials {
  apiUrl: string;
  clientId: string;
  clientSecret: string;
}

interface CachedToken extends KVHash {
  token: string;
  expiresAt: number; // epoch ms
}

const REFRESH_BUFFER_MS = 5 * 60 * 1000;          // refresh 5 min before expiry
const TOKEN_KEY_PREFIX = 'acme_token:';

export function tokenCacheKey(clientId: string): string {
  return `${TOKEN_KEY_PREFIX}${clientId}`;
}

export class AcmeClient {
  private readonly apiUrl: string;
  private readonly clientId: string;
  private readonly clientSecret: string;
  private cachedToken: CachedToken | null = null;

  public constructor(creds: AcmeCredentials) {
    this.apiUrl = creds.apiUrl.replace(/\/+$/, ''); // strip trailing slash
    this.clientId = creds.clientId;
    this.clientSecret = creds.clientSecret;
  }

  public async testCredentials(): Promise<boolean> {
    try {
      await this.fetchToken();
      return true;
    } catch (err: any) {
      logger.warn(`Acme credential test failed: ${err.message}`);
      return false;
    }
  }

  /** Page through records. Translate the cursor/offset to your API's paging scheme. */
  public async listThings(cursor: string | undefined, limit: number): Promise<AcmeListResult> {
    const qs = new URLSearchParams({ limit: String(limit) });
    if (cursor) qs.set('cursor', cursor);
    return this.requestJson<AcmeListResult>('GET', `/things?${qs.toString()}`);
  }

  public async getThing(id: string): Promise<AcmeThing> {
    return this.requestJson<AcmeThing>('GET', `/things/${encodeURIComponent(id)}`);
  }

  private async requestJson<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
    const token = await this.getAccessToken();
    const url = `${this.apiUrl}${path}`;
    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
      Accept: 'application/json',
    };
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    let res = await fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });

    if (res.status === 401) {
      // token may have expired between cache-check and request — invalidate and retry once
      this.cachedToken = null;
      await storage.kvStore.delete(tokenCacheKey(this.clientId));
      const retryToken = await this.getAccessToken();
      headers.Authorization = `Bearer ${retryToken}`;
      res = await fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Acme API ${method} ${path} failed: ${res.status} ${res.statusText}${text ? ` - ${text}` : ''}`);
    }
    return (await res.json()) as T;
  }

  private async getAccessToken(): Promise<string> {
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAt - REFRESH_BUFFER_MS > now) {
      return this.cachedToken.token;
    }
    const stored = await storage.kvStore.get<CachedToken>(tokenCacheKey(this.clientId));
    if (stored?.token && stored.expiresAt && stored.expiresAt - REFRESH_BUFFER_MS > now) {
      this.cachedToken = { token: stored.token, expiresAt: stored.expiresAt };
      return this.cachedToken.token;
    }
    return this.fetchToken();
  }

  private async fetchToken(): Promise<string> {
    const res = await fetch(`${this.apiUrl}/oauth/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        grant_type: 'client_credentials',
        client_id: this.clientId,
        client_secret: this.clientSecret,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`Acme token request failed: ${res.status} ${res.statusText}${text ? ` - ${text}` : ''}`);
    }
    const json = (await res.json()) as { access_token: string; expires_in?: number };
    const token = json.access_token;
    const expiresAt = Date.now() + (json.expires_in ?? 3600) * 1000;
    this.cachedToken = { token, expiresAt };
    await storage.kvStore.put(tokenCacheKey(this.clientId), this.cachedToken);
    return token;
  }
}
```

> If the token is a JWT and the response doesn't include `expires_in`, decode the JWT `exp` claim for the real expiry (`Buffer.from(parts[1], 'base64')` → JSON → `exp * 1000`), and fall back to ~1 hour if decoding fails. The refresh buffer keeps you safe either way.

## Paging schemes

Match your API. The job loop only needs "give me a batch + a cursor for the next batch":

- **Cursor / `endCursor` (GraphQL-style, Shopify):** return `{ items, nextCursor }`; the job stores `nextCursor` and stops when it's null.
- **Offset / `page` + `take`:** the job stores the page number and stops on a short/empty page. Watch for 1-indexed vs 0-indexed APIs.
- **Scroll / continuation token (Elasticsearch-style):** start a scroll once (returns a `scrollId`), then repeatedly "continue" with that id. The cursor lives server-side; the job just stores the `scrollId`. Best for large full exports.

Return a small typed result the job can consume:

```ts
// src/data/AcmeTypes.ts
export interface AcmeListResult {
  items: AcmeThing[];
  nextCursor?: string;   // undefined => no more pages
  totalCount?: number;   // optional, for progress logging
}
```

## Incremental (modified-since) queries

For the scheduled sync, the client needs a way to ask "what changed since T". Most APIs support a `modifiedFrom`/`updated_at_min`/`since` filter plus paging:

```ts
public async listThingsModifiedSince(
  modifiedFrom: string, modifiedTo: string, page: number, take: number,
): Promise<AcmeListResult> {
  return this.requestJson<AcmeListResult>('POST', '/things/query', {
    modifiedFrom, modifiedTo, page, take,
  });
}
```

If the API has **no** modified-since filter, fall back to sorting by `modified desc` and early-exiting once you pass the cursor timestamp — and document the limitation.

## Testing the client (mocked fetch)

No live API needed — stub `global.fetch` and assert request shape + token behavior.

```ts
import { vi, beforeEach, afterEach, describe, it, expect } from 'vitest';
import { resetLocalStores } from '@zaiusinc/app-sdk';
import { AcmeClient } from './AcmeClient';

function mockFetchSequence(responses: Array<() => Response>): void {
  let i = 0;
  global.fetch = vi.fn(async () => responses[Math.min(i++, responses.length - 1)]());
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const tokenOk = () => json({ access_token: 'tok-123', expires_in: 3600 });

describe('AcmeClient', () => {
  const creds = { apiUrl: 'https://api.acme.test', clientId: 'cid', clientSecret: 'sec' };
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => { vi.restoreAllMocks(); resetLocalStores(); });

  it('caches the token across calls', async () => {
    mockFetchSequence([tokenOk, () => json({ items: [] }), () => json({ items: [] })]);
    const c = new AcmeClient(creds);
    await c.listThings(undefined, 50);
    await c.listThings('next', 50);
    expect((global.fetch as any).mock.calls).toHaveLength(3); // 1 token + 2 lists
  });

  it('refreshes and retries on 401', async () => {
    mockFetchSequence([tokenOk, () => new Response('expired', { status: 401 }), tokenOk, () => json({ items: [] })]);
    const c = new AcmeClient(creds);
    await c.listThings(undefined, 50);
    expect((global.fetch as any).mock.calls).toHaveLength(4);
  });

  it('throws a helpful error on non-OK', async () => {
    mockFetchSequence([tokenOk, () => new Response('boom', { status: 500 })]);
    await expect(new AcmeClient(creds).listThings(undefined, 50)).rejects.toThrow(/500/);
  });
});
```
