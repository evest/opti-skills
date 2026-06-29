# Source schema & the transform

The schema is the typed contract for one source. It lives as a YAML file under `src/sources/schema/<name>.yml` and is referenced from `app.yml` by filename (without `.yml`). At runtime your code calls `sources.emit('<Source>', { data })` with an object that matches this schema.

## Where it's wired

```yaml
# app.yml
sources:
  Thing:              # <-- emit name
    description: Acme Thing
    schema: thing      # <-- src/sources/schema/thing.yml
```

```ts
await sources.emit('Thing', { data: payload }); // payload matches thing.yml
```

## Field types

| Type | Notes |
| --- | --- |
| `string` | Text. |
| `long` | Whole numbers (counts, IDs-as-numbers, pixel dimensions). |
| `float` / `decimal` | Floating point (prices, ratings, file sizes). |
| `boolean` | true/false. |
| `[string]`, `[long]`, `[float]`, `[boolean]` | Arrays of primitives. Quote them in YAML: `type: "[string]"`. |
| `[<custom_type>]` | Array of a named custom type, e.g. `type: "[variant]"`. |
| `<custom_type>` | A single named custom type. |

> **There is no `integer` / `int` type** — use `long` for whole numbers. `ocp-app-sdk validate` doesn't recognize `integer` as a scalar; it assumes any unknown type names a custom type and fails with *"type 'integer' does not match any custom_types name"*. (Map a `long` source field to an `integer` field on the destination/CMS side if needed; the destination handles the narrowing.)

Each field has: `name` (snake_case), `type`, `display_name`, optional `description`, and optional `primary: true`.

> **Don't confuse this with OCP's *app data schema*.** OCP has a second, unrelated schema system: "custom objects" under `src/schema/*.yml` (the app's own internal database), with only `string`/`number`/`boolean`/`timestamp` fields and a `relations:` block for joining the app's own tables. That store is queried via the SDK and **does not feed the data sync or Graph** — and its `relations` can neither be added to a source schema nor model a reference that reaches the CMS. Source schemas (this file, under `src/sources/schema/`) are the only thing that emits to Graph; cross-record links between two sources are done with plain **id fields** that the *destination* resolves to content references — not with `relations`.

## Primary key

Exactly one top-level field is `primary: true`. It identifies the record for upserts and is required for delete events. Choose a stable external identifier (the external system's record ID). If the external model is multi-dimensional (e.g. per-locale or per-variant records), decide whether the primary key is the raw ID or a composite like `<id>_<locale>` — this is a modeling decision; confirm with the user.

## Nested custom types

Custom types are reusable nested object shapes declared under `custom_types:` and referenced by name. They can nest arbitrarily (a custom type can contain arrays of other custom types).

```yaml
name: thing
display_name: Things
description: Acme things with variants, prices, and images
fields:
  - name: thing_id
    type: string
    display_name: Thing ID
    description: Acme thing ID
    primary: true
  - name: title
    type: string
    display_name: Title
  - name: description
    type: string
    display_name: Description
  - name: is_active
    type: boolean
    display_name: Is Active
  - name: tags
    type: "[string]"
    display_name: Tags
  - name: created_at
    type: string
    display_name: Created At
    description: ISO 8601 timestamp
  - name: variants
    type: "[variant]"
    display_name: Variants
  - name: images
    type: "[image]"
    display_name: Images

custom_types:
  - name: variant
    display_name: Variant
    description: A purchasable variant of a thing
    fields:
      - name: variant_id
        type: string
        display_name: Variant ID
      - name: sku
        type: string
        display_name: SKU
      - name: price
        type: float
        display_name: Price
      - name: currency
        type: string
        display_name: Currency
      - name: inventory_quantity
        type: long
        display_name: Inventory Quantity
  - name: image
    display_name: Image
    description: A thing image
    fields:
      - name: image_id
        type: string
        display_name: Image ID
      - name: url
        type: string
        display_name: URL
      - name: position
        type: long
        display_name: Position
```

### Schema design tips

- **Flatten for queryability.** The destination (e.g. Optimizely Graph) indexes what you emit. Promote anything a consumer will filter/sort on to a typed top-level field rather than burying it in a free-form blob.
- **Nest children under the parent** (variants, images, prices) so one `emit` carries the whole record. Only split a child into its own source if consumers need to query it as a top-level entity.
- **Per-market/per-locale arrays** (e.g. `prices` with a `market_id`) are a clean way to carry multi-dimensional data in one record.
- **Free-form key/value bags** can be modeled as `[property]` with `key` / `value` / `value_type` fields when the external system has user-defined attributes.

## Required destination metadata (displayName & lastModified)

When the destination is Optimizely Graph (the path to SaaS CMS), **every synced content item must have a non-empty `displayName` and a `lastModified`**. These are `_itemMetadata` fields on the destination side; in the content-type mapping you point one source field at each. If the mapped field is empty for any record, the sync rejects it with `REQUIRED_FIELD_MISSING: displayName` (or `lastModified`) — and one bad record can fail the batch.

Design the source so those fields are **always populated** rather than trusting clean upstream data:

- **`displayName`** — guarantee the field you'll map is never empty. Fall back in the transform: a human label → a secondary label → the primary key.
- **`lastModified`** — map the record's modified timestamp if it has one (normalizing sentinel/empty values). If it has none — common for nested sub-entities promoted to their own source, e.g. images — **synthesize one**: stamp the job's run time and thread it into the transform.

```ts
// run timestamp passed from the job (import start, or incremental window end) — stable across resume
export function transformToPayload(thing: AcmeThing, syncedAt: string): ThingPayload {
  return {
    thing_id: thing.id,
    name: nullable(thing.title) ?? nullable(thing.sku) ?? thing.id, // never empty -> map to displayName
    last_modified: cleanTimestamp(thing.updatedAt) ?? syncedAt,     // -> map to lastModified
    // ...rest
  };
}
```

Then in the destination mapping, map `name → displayName` and `last_modified → lastModified`. This is easy to miss because `ocp-app-sdk validate` passes fine — the requirement is enforced by Graph at sync time, not by schema validation.

## The transform (external record → payload)

Keep this a **pure function** — no SDK calls, no `fetch` — so it's trivially testable. It maps the external system's field names/shape to the schema's snake_case fields and normalizes quirks.

```ts
// src/lib/transformToPayload.ts
import { AcmeThing, AcmeVariant, AcmeImage } from '../data/AcmeTypes';

export interface ThingPayload {
  thing_id: string;
  title: string | null;
  description: string | null;
  is_active: boolean;
  tags: string[];
  created_at: string | null;
  variants: VariantPayload[];
  images: ImagePayload[];
}

export interface VariantPayload {
  variant_id: string;
  sku: string | null;
  price: number | null;
  currency: string | null;
  inventory_quantity: number | null;
}

export interface ImagePayload {
  image_id: string;
  url: string | null;
  position: number | null;
}

export function transformToPayload(thing: AcmeThing): ThingPayload {
  return {
    thing_id: thing.id,
    title: nullable(thing.title),
    description: nullable(thing.description),
    is_active: !!thing.active,
    tags: thing.tags ?? [],
    created_at: cleanTimestamp(thing.createdAt),
    variants: (thing.variants ?? []).map(transformVariant),
    images: (thing.images ?? []).map(transformImage),
  };
}

function transformVariant(v: AcmeVariant): VariantPayload {
  return {
    variant_id: v.id,
    sku: nullable(v.sku),
    price: nullableNumber(v.price),
    currency: nullable(v.currency),
    inventory_quantity: nullableNumber(v.inventory),
  };
}

function transformImage(img: AcmeImage): ImagePayload {
  return {
    image_id: img.id,
    url: nullable(img.url),
    position: nullableNumber(img.position),
  };
}

function nullable(v: string | undefined | null): string | null {
  return v === undefined || v === null || v === '' ? null : v;
}

function nullableNumber(v: number | undefined | null): number | null {
  return v === undefined || v === null ? null : v;
}

// Many systems use a sentinel "zero date" for unset timestamps — normalize to null.
function cleanTimestamp(v: string | undefined | null): string | null {
  if (!v) return null;
  if (v.startsWith('0001-01-01')) return null; // adjust sentinel to your system
  return v;
}
```

### Common normalizations

- **Sentinel dates** (`0001-01-01T00:00:00`, `1970-01-01`, etc.) → `null`.
- **Empty strings** → `null` for optional fields, so the destination doesn't index meaningless values.
- **Missing booleans** → `false` via `!!value`.
- **Absent numbers** → `null` (not `0`), so "no price" is distinguishable from "free".
- **Comma-joined tag strings** → arrays (`"a, b".split(',').map(s => s.trim())`).

## Deletes

If the source can detect deletions, emit the primary key with `_isDeleted: true`:

```ts
await sources.emit('Thing', { data: { thing_id: id, _isDeleted: true } });
```

The sync service routes the delete to configured destinations. You typically emit this from a webhook on a delete event, or from an incremental job that queries a "deleted since" feed if the API offers one.

## Static vs dynamic schemas

- **Static** (this skill's default): a fixed `.yml` file. Use when the record shape is known at build time.
- **Dynamic**: a TypeScript class extending `SourceSchemaFunction` that returns the schema at runtime, referenced from `app.yml` via an `entry_point`. Use only when different installs have genuinely different fields (e.g. user-defined custom fields per tenant). See the [Source docs](https://docs.developers.optimizely.com/optimizely-connect-platform/docs/source).
