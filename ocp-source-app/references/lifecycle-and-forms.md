# Lifecycle & settings form

The **settings form** (`forms/settings.yml`) renders the app's configuration UI inside the OCP tracker. The **Lifecycle** class (`src/lifecycle/Lifecycle.ts`) handles events from that form plus install/uninstall/upgrade. Together they: collect and validate credentials, expose a "Run Full Import" button, and clean up on uninstall.

## Settings form

Three sections is the typical shape: credentials, sync options, and an import action. Field types include `text`, `secret` (masked), `toggle`, `button`, and `instructions` (static help text). A `dataType: number` hints numeric input.

```yaml
# forms/settings.yml
sections:
  - key: acme_credentials
    label: Acme Credentials
    elements:
      - key: api_url
        type: text
        label: Acme API URL
        required: true
        help: Base URL of the Acme API (e.g. https://api.acme.example)
      - key: client_id
        type: text
        label: Client ID
        required: true
      - key: client_secret
        type: secret
        label: Client Secret
        required: true
        help: Stored encrypted; never displayed back.

  - key: sync_options
    label: Sync Options
    elements:
      - key: batch_size
        type: text
        dataType: number
        label: Batch Size
        required: true
        help: Records fetched per API request during import (default 50).
      - key: incremental_lookback_minutes
        type: text
        dataType: number
        label: Incremental Lookback (minutes)
        required: true
        help: On the first scheduled run with no cursor, how far back to look (default 120).

  - key: import_actions
    label: Import
    elements:
      - type: instructions
        text: |
          Run a full import of all Acme records. Subsequent changes are picked up
          automatically by the scheduled incremental sync.
      - key: trigger_full_import
        type: button
        label: Run Full Import
        action: trigger_full_import      # matched in Lifecycle.onSettingsForm
        help: Triggers a full import to all configured syncs.
```

### Optional: status properties

You can declare `properties:` on a section and read/write them from the Lifecycle to show dynamic status (e.g. "Webhooks: Active"). Use `instructions` elements with a `visible:` condition keyed on a property to switch help text based on state. (The Shopify reference app uses this to surface webhook status.)

## Lifecycle

`onSettingsForm(section, action, formData)` is the workhorse: it fires when any section is saved or any button is pressed. Branch on `action` first (buttons), then on `section` (saves). Validate credentials by making a real auth call **before** persisting them.

```ts
import {
  Lifecycle as AppLifecycle, AuthorizationGrantResult, jobs,
  LifecycleResult, LifecycleSettingsResult, logger, Request, storage, SubmittedFormData,
} from '@zaiusinc/app-sdk';
import { AcmeClient } from '../lib/AcmeClient';

export class Lifecycle extends AppLifecycle {
  public async onInstall(): Promise<LifecycleResult> {
    try {
      logger.info('Installing Acme Source');
      return { success: true };
    } catch (err: any) {
      return { success: false, retryable: true, message: `Install error: ${err}` };
    }
  }

  public async onSettingsForm(
    section: string, action: string, formData: SubmittedFormData,
  ): Promise<LifecycleSettingsResult> {
    const result = new LifecycleSettingsResult();
    try {
      if (action === 'trigger_full_import') return this.handleTriggerFullImport(result);
      if (section === 'acme_credentials') return this.handleCredentials(formData, result);

      await storage.settings.put(section, formData); // default: persist other sections as-is
      return result;
    } catch (err: any) {
      logger.error(`onSettingsForm error: ${err.message}`);
      return result.addToast('danger', 'An unexpected error occurred. Please try again.');
    }
  }

  private async handleTriggerFullImport(result: LifecycleSettingsResult): Promise<LifecycleSettingsResult> {
    const creds: Record<string, string> = await storage.settings.get('acme_credentials');
    if (!creds.api_url || !creds.client_id || !creds.client_secret) {
      return result.addToast('danger', 'Configure your Acme credentials before running an import.');
    }
    await jobs.trigger('import_things', {});
    return result.addToast('success', 'Full import triggered. You will be notified when it completes.');
  }

  private async handleCredentials(
    formData: SubmittedFormData, result: LifecycleSettingsResult,
  ): Promise<LifecycleSettingsResult> {
    const apiUrl = (formData.api_url as string)?.trim();
    const clientId = (formData.client_id as string)?.trim();
    const clientSecret = (formData.client_secret as string)?.trim();
    if (!apiUrl || !clientId || !clientSecret) {
      return result.addToast('danger', 'Provide an API URL, client ID, and client secret.');
    }

    const client = new AcmeClient({ apiUrl, clientId, clientSecret });
    if (!(await client.testCredentials())) {
      return result.addToast('danger', 'Invalid Acme credentials. Check the URL, client ID, and secret.');
    }

    await storage.settings.put('acme_credentials', {
      api_url: apiUrl, client_id: clientId, client_secret: clientSecret,
    });
    return result.addToast('success', `Connected to Acme at ${apiUrl}.`);
  }

  // OAuth-style flows are not used for client-credentials auth.
  public async onAuthorizationRequest(): Promise<LifecycleSettingsResult> {
    return new LifecycleSettingsResult().addToast('danger', 'OAuth is not supported; use client credentials.');
  }
  public async onAuthorizationGrant(_req: Request): Promise<AuthorizationGrantResult> {
    return new AuthorizationGrantResult('').addToast('danger', 'OAuth is not supported.');
  }

  public async onUpgrade(_from: string): Promise<LifecycleResult> { return { success: true }; }
  public async onFinalizeUpgrade(_from: string): Promise<LifecycleResult> { return { success: true }; }
  public async onAfterUpgrade(): Promise<LifecycleResult> { return { success: true }; }

  public async onUninstall(): Promise<LifecycleResult> {
    try {
      const creds: Record<string, string> = await storage.settings.get('acme_credentials');
      if (creds?.client_id) await storage.kvStore.delete(`acme_token:${creds.client_id}`);
      await storage.kvStore.delete('acme_sync:cursor');
      return { success: true };
    } catch (err: any) {
      return { success: true, message: `Warning during uninstall: ${err.message}` };
    }
  }
}
```

### Key Lifecycle points

- **Validate before persisting.** Make a real `testCredentials()` call; only `storage.settings.put` on success. A `danger` toast on failure leaves old settings intact.
- **`LifecycleSettingsResult`** is chainable: `result.addToast('success'|'danger'|'warning', msg)`, `result.redirect(url)`, etc.
- **Clean up on uninstall.** Delete cached tokens and cursors from `kvStore`. You can't delete already-emitted records — that's the destination's concern.
- **`onInstall` retryable.** Return `{ success: false, retryable: true }` for transient install errors so OCP retries.

## Option: real-time webhooks instead of scheduled sync

If the external system can call out, you can replace (or complement) the scheduled job with a **function** that receives events. Declare it in `app.yml`:

```yaml
functions:
  thing_webhook:
    entry_point: ThingWebhook
    description: Receives Acme thing change events for real-time sync
```

The function reads the payload and emits — handling deletes via `_isDeleted`:

```ts
import { Function, Request, Response, sources, storage, logger } from '@zaiusinc/app-sdk';
import { AcmeClient } from '../lib/AcmeClient';
import { transformToPayload } from '../lib/transformToPayload';

export class ThingWebhook extends Function {
  public constructor(request: Request) { super(request); }

  public async perform(): Promise<Response> {
    try {
      const event = this.request.bodyJSON as { id: string; type: string };
      if (!event?.id) return new Response(400, 'Missing thing id');

      if (event.type === 'thing.deleted') {
        await sources.emit('Thing', { data: { thing_id: event.id, _isDeleted: true } });
        return new Response(200, { ok: true });
      }

      // Re-fetch the full record so the payload is complete (webhook bodies are often partial).
      const creds: Record<string, string> = await storage.settings.get('acme_credentials');
      const client = new AcmeClient({
        apiUrl: creds.api_url, clientId: creds.client_id, clientSecret: creds.client_secret,
      });
      const thing = await client.getThing(event.id);
      await sources.emit('Thing', { data: transformToPayload(thing) as any });
      return new Response(200, { ok: true });
    } catch (err: any) {
      logger.error(`Webhook error: ${err.message}`);
      return new Response(500, { ok: false, error: err.message });
    }
  }
}
```

**Registering webhooks** belongs in `onSettingsForm` after credentials validate: get the endpoint URL via `functions.getEndpoints()` (returns a map keyed by function name, e.g. `endpoints['thing_webhook']`), then call the external system's webhook-registration API. Delete them in `onUninstall`. A small `WebhookManager` class that wraps create/delete keeps the Lifecycle readable. Persist a `webhooks_active` flag in settings so the form can show status.

### Webhook vs scheduled — choosing

| | Scheduled incremental | Webhooks |
| --- | --- | --- |
| Connectivity | Outbound only (always works) | External system must reach your function URL |
| Latency | Up to one cron interval | Near real-time |
| Completeness | Catches everything in the window | Can miss events if delivery fails — pair with a periodic reconcile |
| Complexity | Low | Registration + signature verification + retries |

A robust setup uses **both**: webhooks for latency, a scheduled job as a safety net.
