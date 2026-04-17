# Registration (`lib/optimizely/init.ts`)

The single entry point that tells the SDK about every content type, every React component, and every display template in your app.

## Anatomy

```ts
// lib/optimizely/init.ts
import {
  BlankExperienceContentType,
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
} from '@optimizely/cms-sdk'
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server'

// Imports: every content-type + component tuple
import HeroBlock, {
  HeroBlockContentType,
} from '@/components/optimizely/block/hero-block'
import CMSPage, {
  CMSPageContentType,
} from '@/components/optimizely/page/CMSPage'
import BlankExperience from '@/components/optimizely/experience/BlankExperience'
import BlankSection from '@/components/optimizely/section/BlankSection'
import ProfileBlock, {
  ProfileBlockContentType,
  ProfileBlockDisplayTemplate,
} from '@/components/optimizely/block/profile-block'

// 1. Content types — tells the SDK how to resolve __typename, validate shapes,
//    and traverse nested fields. Must include every type referenced by your
//    schemas, including built-ins you use (BlankExperienceContentType).
initContentTypeRegistry([
  HeroBlockContentType,
  ProfileBlockContentType,
  CMSPageContentType,
  BlankExperienceContentType,
])

// 2. React components — maps content-type keys to default exports. The
//    resolver key is the content-type KEY (e.g. 'HeroBlock'), NOT the
//    content-type object. Here the shorthand `{ HeroBlock }` uses ES object
//    shorthand because the variable name matches the key.
initReactComponentRegistry({
  resolver: {
    HeroBlock,
    ProfileBlock,
    CMSPage,
    BlankExperience,
    BlankSection,
  },
})

// 3. Display templates — optional visual variants registered separately.
initDisplayTemplateRegistry([ProfileBlockDisplayTemplate])
```

## Loading order

```
app/layout.tsx  ─→ import '@/lib/optimizely/init'     (side-effect import)
                   └─ runs all three `init*Registry` calls at module-evaluation time
                      (re-executes per request in dev; effectively per server boot in prod
                       depending on deployment model — serverless cold-starts re-run it)
```

The import must happen **before any `OptimizelyComponent` is rendered**. Placing it in the root layout guarantees this: Next.js evaluates the root layout module before any page module, and the side-effect import runs synchronously during that evaluation.

Do **not** lazy-load, do **not** import only from some pages, do **not** put it inside a `useEffect`.

### Why `init.ts` and not `layout.tsx` directly

You could in principle put all three `init*Registry` calls inline in `app/layout.tsx`. Don't. The layout would have to import every block, page, experience, section, and display template — turning the root layout into a config dumping ground. `init.ts` is the bootstrap equivalent of a DI container registration module: one file whose only job is wiring, kept separate from HTML-shell concerns.

## Asymmetric failure modes — the key gotcha

Forgetting to register a content type produces a **loud** CLI error during `opti-push`:
> Error: Content type 'HeroBlock' referenced but not in registry.

Forgetting to register a React component produces a **silent** blank render:
> `OptimizelyComponent` receives a `__typename` the resolver doesn't know about, falls back to rendering nothing, no log, no exception.

This asymmetry is the dominant debugging story. Rule: whenever something renders blank for a specific content type, check `initReactComponentRegistry.resolver` first. Always. Before any other hypothesis.

The only other silent miss at this layer: a content-type file placed outside `./components/optimizely/**/*.tsx`. The CLI scan won't find it; `opti-push` pushes nothing; the CMS editor never shows the new type. No error.

## The three-registry contract

| Registry call | If omitted | If out of order |
|---|---|---|
| `initContentTypeRegistry([...])` | `OptimizelyComponent` can't resolve `__typename` → renders nothing or throws | Types must be registered before the React registry uses them at render time; call order within the file is conventional (content types first, components second, display templates third) |
| `initReactComponentRegistry({ resolver })` | `OptimizelyComponent` renders nothing for content whose key isn't in the map | — |
| `initDisplayTemplateRegistry([...])` | Display templates are ignored; components receive `displaySettings: undefined` | — |

Only `initContentTypeRegistry` is strictly sequential with the others. In practice always call them in the order above.

## Resolver object forms

The resolver accepts multiple shapes:

### Flat map (most common)
```ts
initReactComponentRegistry({
  resolver: {
    HeroBlock,
    CMSPage,
  },
})
```

### Tag variants (for `:Tag` suffix rendering)
```ts
initReactComponentRegistry({
  resolver: {
    'Tile':          DefaultTile,
    'Tile:Square':   SquareTile,
    'Tile:Outlined': OutlinedTile,
  },
})
```

The SDK looks up `ContentType:Tag` first, falls back to `ContentType` if no tag match. Tag is read from `content.__tag` at render time.

### Function resolver
```ts
initReactComponentRegistry({
  resolver: (contentType, options) => {
    if (contentType === 'Button') {
      return options?.tag === 'primary' ? PrimaryButton : DefaultButton
    }
    return undefined
  },
})
```

Useful for dynamic/computed lookups. Return `undefined` to fall back to the SDK default (which typically renders nothing).

## Separating the content-type list for re-use

Pages that allow blocks as children reference a shared list in `AllBlocksContentTypes`:

```ts
// lib/optimizely/content-types.ts
import { HeroBlockContentType } from '@/components/optimizely/block/hero-block'
import { ProfileBlockContentType } from '@/components/optimizely/block/profile-block'
// ... every block that should be placeable inside a CMSPage.blocks array

export const AllBlocksContentTypes = [
  HeroBlockContentType,
  ProfileBlockContentType,
]
```

Then in a page schema:
```ts
export const CMSPageContentType = contentType({
  key: 'CMSPage',
  baseType: '_page',
  properties: {
    blocks: {
      type: 'array',
      items: { type: 'content', allowedTypes: AllBlocksContentTypes },
      localized: true,
    },
  },
})
```

This keeps the "allowed child types" list in one place — when you add a new block, you add it here once.

## Adding a new content type — full checklist

1. **Create** `components/optimizely/block/<name>.tsx` co-locating:
   - `export const XContentType = contentType({...})`
   - `export default function X({ content }: { content: ContentProps<typeof XContentType> }) {...}`
2. **Register in `lib/optimizely/init.ts`:**
   - Add to `initContentTypeRegistry([...])`
   - Add to `initReactComponentRegistry({ resolver: {...} })`
3. **Allow in pages** — add to `AllBlocksContentTypes` in `lib/optimizely/content-types.ts` if the block should be placeable inside `CMSPage.blocks`.
4. **Push to CMS:** `npm run opti-push`.
5. **Verify:** the block appears in the CMS editor's block picker.

Missing any of 1–4 produces a different failure:
- Missing schema export → CLI push doesn't find it → block doesn't appear in CMS editor
- Missing `initContentTypeRegistry` entry → SDK can't resolve `__typename` → `OptimizelyComponent` renders nothing
- Missing `initReactComponentRegistry` entry → SDK has type info but no component → renders nothing
- Missing `AllBlocksContentTypes` entry → block appears globally but not insertable inside `CMSPage`

## Built-in content types

The SDK ships built-ins that you use but should not redefine:
- `BlankExperienceContentType`
- `BlankSectionContentType`

Include them in `initContentTypeRegistry` if your app renders them. The React component wrappers (`BlankExperience`, `BlankSection`) are **your** code — the SDK only provides the schema constants.
