# Visual Builder Rendering

Experiences and sections use the SDK's `OptimizelyComposition` and `OptimizelyGridSection` components to render nested node trees assembled in Visual Builder.

## Three baseTypes collaborate

- `_experience` — the outer container; renders a flat list of composition nodes via `OptimizelyComposition`.
- `_section` — a grid-capable container; renders rows/columns via `OptimizelyGridSection`.
- `_component` with `compositionBehaviors: ['sectionEnabled']` — a block that editors can use as a top-level item in an experience.

The `BlankExperienceContentType` and `BlankSectionContentType` constants are SDK built-ins — include them in `initContentTypeRegistry` but you supply the React components (`BlankExperience`, `BlankSection`).

## BlankExperience — the canonical experience wrapper

```tsx
// components/optimizely/experience/BlankExperience.tsx
import { BlankExperienceContentType, ContentProps } from '@optimizely/cms-sdk'
import {
  ComponentContainerProps,
  OptimizelyComposition,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server'

type Props = { content: ContentProps<typeof BlankExperienceContentType> }

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node)
  return <div {...pa(node)}>{children}</div>
}

export default function BlankExperience({ content }: Props) {
  return (
    <main className="blank-experience">
      <OptimizelyComposition
        nodes={content.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  )
}
```

### `OptimizelyComposition` contract

| Prop | Type | Purpose |
|---|---|---|
| `nodes` | `ExperienceNode[]` | Flat list from `content.composition.nodes` |
| `ComponentWrapper` | `({children, node}) => JSX.Element` | Optional. Wraps each top-level component node. Spread `{...pa(node)}` on the outermost element so editors can click-to-edit. |

Each node is either a component node (has `component` + metadata) or a structure node (row/column/section). `OptimizelyComposition` recursively renders both, delegating component resolution to `OptimizelyComponent` (which reads `initReactComponentRegistry`).

## BlankSection — the canonical grid wrapper

```tsx
// components/optimizely/section/BlankSection.tsx
import { BlankSectionContentType, ContentProps } from '@optimizely/cms-sdk'
import {
  OptimizelyGridSection,
  StructureContainerProps,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server'

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node)
  return (
    <div
      className="vb:row flex flex-1 flex-col flex-nowrap md:flex-row"
      {...pa(node)}
    >
      {children}
    </div>
  )
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node)
  return (
    <div
      className="vb:col flex flex-1 flex-col flex-nowrap justify-start"
      {...pa(node)}
    >
      {children}
    </div>
  )
}

type Props = { content: ContentProps<typeof BlankSectionContentType> }

export default function BlankSection({ content }: Props) {
  const { pa } = getPreviewUtils(content)
  return (
    <section
      className="vb:grid relative flex w-full flex-col flex-wrap"
      {...pa(content)}
    >
      <OptimizelyGridSection nodes={content.nodes} row={Row} column={Column} />
    </section>
  )
}
```

### `OptimizelyGridSection` contract

| Prop | Type | Purpose |
|---|---|---|
| `nodes` | `ExperienceNode[]` | From `content.nodes` (note: NOT `content.composition.nodes` — sections use a flatter shape) |
| `row` | `(props: StructureContainerProps) => JSX.Element` | Optional. Wraps each row. |
| `column` | `(props: StructureContainerProps) => JSX.Element` | Optional. Wraps each column. |
| `displaySettings` | `DisplaySettingsType[]` | Optional. Per-node display settings. |

Defaults to SDK-provided row/column wrappers if you omit the props. Always provide your own to apply layout styling and preview attributes.

### The `vb:` class prefix

Visual Builder expects:
- `vb:grid` on the outer `<section>`
- `vb:row` on each row
- `vb:col` on each column

These aren't Tailwind classes — they're **marker classes** the Visual Builder UI looks for to identify layout regions. Keep them. If they're missing, the editor UI can't position drop zones correctly.

## `getPreviewUtils(node)` — what `pa()` returns

```ts
const { pa, src } = getPreviewUtils(node)
```

### `pa(target?)` → data attributes for click-to-edit

```tsx
<h1 {...pa('title')}>{content.title}</h1>          // property-scoped edit
<div {...pa(node)}>{children}</div>                 // node-scoped edit
<div {...pa(content)}>{children}</div>              // content-scoped edit
<div {...pa({ key: 'customId' })}>                  // custom key form
```

- In **preview/edit mode**, returns attributes like `{'data-epi-property-name': 'title'}` or `{'data-epi-block-id': 'abc123'}`.
- In **published mode**, returns `{}` — the spread is a no-op.

You can spread on any element; it's always safe.

### `src(input)` → preview-aware URLs

```tsx
const { src } = getPreviewUtils(content)
<img src={src(content.image)} alt="" />
```

Appends preview tokens to image URLs when rendering in preview mode so unpublished asset versions resolve. In published mode, returns the URL unchanged. Omit this and draft images won't load in preview.

## `data-epi-edit` on leaf elements

For non-Visual-Builder blocks (plain `_component` types), you annotate editable text/attributes directly:

```tsx
<h1 data-epi-edit="title">{title}</h1>
<p  data-epi-edit="subtitle">{subtitle}</p>
```

The attribute value is the property key from the content-type schema. This is lower-level than `pa()` — use it in regular blocks; use `pa()` in experience/section wrappers where the target is a node, not a named property.

### Exact-match requirement — common silent failure

The attribute value is matched character-for-character against the keys in the `contentType()` definition:

```tsx
// contentType declares { title: ..., subtitle: ... }
<h1 data-epi-edit="title">{title}</h1>       // ✓ click-to-edit works
<p  data-epi-edit="sub-title">{subtitle}</p> // ✗ mismatch — click-to-edit silently disabled for subtitle
<p  data-epi-edit="Subtitle">{subtitle}</p>  // ✗ case mismatch — silently disabled
```

Only that one field loses click-to-edit; the rest of the component still works. The editor sees no error, just no inline-edit affordance on the broken field. When troubleshooting "field X can't be clicked in preview but others can", check the attribute value first.

## `compositionBehaviors` — letting a block be a section

If a block should be placeable as a top-level Visual Builder node (not just nested inside a section), mark it:

```ts
export const HeroBlockContentType = contentType({
  key: 'HeroBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: { ... },
})
```

Valid values:
- `'sectionEnabled'` — block can appear as a section in an experience
- `'elementEnabled'` — block can appear as an inline element inside a section

`_element` is a separate baseType; don't use `'elementEnabled'` on `_component` unless you specifically need the dual use case (content-types skill covers the distinction).

## Display templates on composition nodes

If a content type has multiple display templates, the editor picks one per placement. At render time:

```tsx
// The SDK passes displaySettings as a second component prop
export default function ProfileBlock({
  content: { name, title, bio },
  displaySettings,
}: {
  content: ContentProps<typeof ProfileBlockContentType>
  displaySettings?: Record<string, string>
}) {
  const colorScheme = displaySettings?.colorScheme ?? 'default'
  return <section className={backgroundVariants({ colorScheme })}>...</section>
}
```

Register the template via `initDisplayTemplateRegistry([ProfileBlockDisplayTemplate])`. See the content-types skill for template definition syntax.

## Debugging Visual Builder rendering

- **Nodes render but can't be edited** → missing `{...pa(node)}` on the wrapper element.
- **Drop zones don't appear in editor** → missing `vb:grid` / `vb:row` / `vb:col` classes.
- **"Component not found" in render** → the composition references a content type that isn't in `initReactComponentRegistry.resolver`.
- **Layout styles applied twice / conflicting** → you probably wrapped both `<BlankExperience>` and a section inside another layout container; Visual Builder already handles nesting.
- **Images load in preview but not in edit** → missing `src()` wrapping; use `getPreviewUtils.src(content.image)` instead of `content.image` directly.

## Where this pattern lives in the SDK

- `OptimizelyComposition`, `OptimizelyGridSection`, `getPreviewUtils`, `ComponentContainerProps`, `StructureContainerProps` — all from `@optimizely/cms-sdk/react/server`.
- `BlankExperienceContentType`, `BlankSectionContentType` — from `@optimizely/cms-sdk`.
- Official reference: `D:\Dev\content-js-sdk\docs\8-experience.md`.
