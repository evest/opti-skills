# Registration (`src/optimizely.ts`)

The single entry point that tells the SDK about every content type, every React component, every display template — and configures the Graph client.

## Anatomy

```ts
// src/optimizely.ts
import {
  config,
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

// Schema modules — each file exports a `…CT` const built with contentType()
import * as contentTypes from '@/content-types';

// Display template modules — each exports a `…DisplayTemplate` const built with displayTemplate()
import * as displayTemplates from '@/display-templates';

// React components — `pages/blocks/elements/experiences` re-exported from src/components/index.ts
import * as components from '@/components';

import { getGraphGatewayUrl } from '@/lib/config';

// 1. Configure the Graph client once. getClient() reads from this config —
//    every fetcher uses getClient() instead of `new GraphClient()`.
if (process.env.OPTIMIZELY_GRAPH_SINGLE_KEY) {
  config({
    apiKey: process.env.OPTIMIZELY_GRAPH_SINGLE_KEY,
    graphUrl: getGraphGatewayUrl(),
    // Optional:
    // host: 'https://example.com',           // multi-site default filter
    // maxFragmentThreshold: 100,             // raise only if you understand why
    // cache: true,                           // SDK-side cache; default true
  });
}

// 2. Content types — the SDK uses these to resolve __typename, validate
//    shapes, traverse nested fields, and emit GraphQL fragments.
//    initContentTypeRegistry REPLACES the registry — built-ins are NOT
//    auto-merged. Add them explicitly when used.
initContentTypeRegistry([
  ...Object.values(contentTypes),
  BlankExperienceContentType,
  BlankSectionContentType,
]);

// 3. Display templates — visual variants registered separately.
initDisplayTemplateRegistry([...Object.values(displayTemplates)]);

// 4. React components — maps content-type KEY (string) to default export.
//    Object shorthand `{ HeroBlock }` works when the variable name matches
//    the content-type key.
initReactComponentRegistry({
  resolver: {
    ArticlePage: components.ArticlePage,
    HeroBlock: components.HeroBlock,
    BlankExperience: components.BlankExperience,
    BlankSection: components.BlankSection,
    // ... one entry per content-type key in CMS content
  },
});
```

## `config()` vs `new GraphClient()`

v2 added `config({...})` + `getClient()` so callers don't have to construct a client per-fetch. Construct in one place, read everywhere:

```ts
// Anywhere a fetch is needed
import { getClient } from '@optimizely/cms-sdk';
const client = getClient();
const items = await client.getContentByPath('/no/about/');
```

`new GraphClient(key, options)` still works for explicit construction (the webhook in `src/app/hooks/graph/route.ts` uses raw `fetch()` because it's at the module-load layer, but a `new GraphClient()` would also work). For app code, prefer `getClient()`.

### Why prefer `getClient()`

- Single config point — change API key/Graph URL in one place
- No env-var threading through every page/component
- `'use cache'` functions stay deterministic by argument shape (the client is implicit, not part of the key)

## Loading order

```
src/app/layout.tsx ─→ import '@/optimizely'   (side-effect import)
                       └─ runs config() + all three init*Registry() calls
                          at module-evaluation time (re-runs per dev edit,
                          once per server cold-start in production)
```

The import must happen **before any `OptimizelyComponent` is rendered**. Placing it in the root layout guarantees this: Next.js evaluates the root layout module before any page module, and the side-effect import runs synchronously during evaluation.

Do **not** lazy-load. Do **not** import only from some pages. Do **not** put it inside a `useEffect`.

### Why `optimizely.ts` and not `layout.tsx` directly

You could put all four calls inline in `app/layout.tsx`. Don't. The layout would have to import every content type, every component, every display template — turning it into a config dumping ground. `optimizely.ts` is the bootstrap equivalent of a DI container registration module: one file whose only job is wiring, kept separate from HTML-shell concerns.

## Asymmetric failure modes — the key gotcha

Forgetting to register a content type produces a **loud** CLI error during `cms:push-config`:
> Error: Content type 'HeroBlock' referenced but not in registry.

Forgetting to register a React component produces a **silent** blank render:
> `OptimizelyComponent` receives a `__typename` the resolver doesn't know about, falls back to rendering nothing — no log, no exception.

This asymmetry is the dominant debugging story. Rule: whenever something renders blank for a specific content type, check `initReactComponentRegistry.resolver` first. Always. Before any other hypothesis.

The other silent miss: a content-type file outside the `components` glob in `optimizely.config.mjs`. The CLI scan won't find it; `cms:push-config` pushes nothing; the CMS editor never sees the new type. No error.

## The four-call contract

| Call | If omitted | If out of order |
|---|---|---|
| `config({...})` | `getClient()` returns a client with no config — fetches fail at runtime with "missing apiKey" | Must run before any `getClient()` call. Per convention, first in the file. |
| `initContentTypeRegistry([...])` | `OptimizelyComponent` can't resolve `__typename` → renders nothing or throws | Must precede render. By convention, second. |
| `initDisplayTemplateRegistry([...])` | Display templates ignored; components receive `displaySettings: undefined` | Position-independent in practice, but conventionally third. |
| `initReactComponentRegistry({ resolver })` | `OptimizelyComponent` renders nothing for content whose key isn't in the map | Last; resolver receives requests post-init. |

Only `config` is strictly required to come first (because the others are pure registry mutations). In practice, always call them in the order above.

## Resolver shapes

The resolver accepts multiple shapes:

### Flat map (most common)
```ts
initReactComponentRegistry({
  resolver: {
    HeroBlock,
    ArticlePage,
  },
});
```

### Tag variants — object form (recommended for ≥2 variants)
```ts
initReactComponentRegistry({
  resolver: {
    Tile: {
      default: DefaultTile,
      tags: {
        Square: SquareTile,
        Outlined: OutlinedTile,
      },
    },
  },
});
```

### Tag variants — colon form (concise for 1)
```ts
initReactComponentRegistry({
  resolver: {
    'Tile': DefaultTile,
    'Tile:Square': SquareTile,
  },
});
```

The SDK first checks `Tile:<tag>`, falls back to `Tile`. Tag is read from the content's display-template `tag` field.

### Function resolver
```ts
initReactComponentRegistry({
  resolver: (contentType, options) => {
    if (contentType === 'Button') {
      return options?.tag === 'primary' ? PrimaryButton : DefaultButton;
    }
    return undefined;
  },
});
```

Useful for dynamic/computed lookups. Return `undefined` to fall back to the SDK default (which renders nothing).

## Built-in content types

The SDK ships built-ins you use but should not redefine:
- `BlankExperienceContentType`
- `BlankSectionContentType`

Include them in `initContentTypeRegistry` if your CMS content references them (the default Visual Builder experience and section types do). The React component wrappers (`BlankExperience`, `BlankSection`) are **your** code — the SDK only provides the schema constants.

```ts
import {
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';

initContentTypeRegistry([
  ...Object.values(contentTypes),
  BlankExperienceContentType,
  BlankSectionContentType,
]);
```

Omit `BlankSectionContentType` and Visual Builder sections will render blank when the editor places one. Omit `BlankExperienceContentType` and experiences render blank.

## Adding a new content type — full checklist

1. **Define the schema** (see `optimizely-cms-content-types` skill): create `src/content-types/NewType.ts` with `export const NewTypeCT = contentType({...})`.
2. **Export from the barrel**: add to `src/content-types/index.ts` so the wildcard import in `src/optimizely.ts` picks it up.
3. **Build the React component**: create `src/components/{pages,blocks,elements,experiences}/NewType.tsx` with `export default function NewType({ content }: { content: ContentProps<typeof NewTypeCT> }) {...}`.
4. **Export from `src/components/index.ts`** so wildcard import picks it up.
5. **Register in `src/optimizely.ts`**: the resolver entry. If the content-type key matches the component variable name, shorthand `{ NewType }` works.
6. **Add to `optimizely.config.mjs`**: include the file path (or rely on a glob).
7. **Push to CMS**: `npm run cms:push-config`.
8. **Verify**: the type shows up in the CMS editor's block/page picker.

Missing any of 1–7 produces a different failure mode:
- Missing schema file → CLI doesn't push it → editor never sees the type
- Missing barrel export → schema not registered → `OptimizelyComponent` can't resolve `__typename` → blank render
- Missing React component or barrel export → resolver entry references undefined → blank render
- Missing resolver entry → CMS content references a key the resolver doesn't know → blank render
- Missing path in `optimizely.config.mjs` → CLI doesn't push the schema (same as #1)
- Missing `cms:push-config` run → schema in code, not in CMS → editor doesn't see the type

## Pattern: barrel exports for wildcard registration

Using `import * as contentTypes from '@/content-types'` and `[...Object.values(contentTypes)]` means a new type registers automatically once you add it to `src/content-types/index.ts`. Same for display templates and components.

The trade-off: every export must be a content-type constant. Don't put type-only exports or utility functions in the barrel — `Object.values()` would include them and `initContentTypeRegistry` would reject the non-content-type entries.

If you need utilities alongside the schema, put them in a separate file:
```
src/content-types/
  index.ts           — only `export { XCT } from './X'` lines
  ArticlePage.ts     — exports ArticlePageCT only
  HeroBlock.ts       — exports HeroBlockCT only
  _shared.ts         — utility types (filename prefixed with _ to skip the glob)
```

## Component `index.ts` must match resolver keys

The barrel re-exports in `src/components/index.ts` use the file's default export. The key in `initReactComponentRegistry.resolver` must match the **content-type key**, not the file name. Conventions:

- Content-type key: `HeroBlock` (PascalCase, no suffix)
- Schema constant: `HeroBlockCT` (PascalCase + `CT`)
- File name: `HeroBlock.tsx` (matches the key)
- Component default export: `HeroBlock` (matches the key)
- Resolver entry: `HeroBlock: components.HeroBlock` (or shorthand `HeroBlock`)

Mismatch any of these and you get a silent blank render.
