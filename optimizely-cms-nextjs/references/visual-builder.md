# Visual Builder Rendering

Experiences and sections use the SDK's `OptimizelyComposition` and `OptimizelyGridSection` to render nested node trees assembled in Visual Builder.

## Three baseTypes collaborate

- `_experience` — the outer container; renders a flat list of composition nodes via `OptimizelyComposition`.
- `_section` — a grid-capable container; renders rows/columns via `OptimizelyGridSection`.
- `_component` with `compositionBehaviors: ['sectionEnabled']` — a block that editors can place as a top-level item in an experience.
- `_component` with `compositionBehaviors: ['elementEnabled']` — a block that editors can place as an element inside a section's grid (with property-type restrictions; see content-types skill).

There is **no separate `_element` baseType**. Elements are just `_component` types with `elementEnabled`. See the `optimizely-cms-content-types` skill for the schema-side concerns (element property restrictions, etc.).

The `BlankExperienceContentType` and `BlankSectionContentType` constants are SDK built-ins — include them in `initContentTypeRegistry` but supply your own React components (`BlankExperience`, `BlankSection`).

## BlankExperience — canonical experience wrapper

```tsx
// src/components/experiences/BlankExperience.tsx
import { BlankExperienceContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  ComponentContainerProps,
  OptimizelyComposition,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';

type Props = { content: ContentProps<typeof BlankExperienceContentType> };

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="mb-2" {...pa(node)}>{children}</div>;
}

export default function BlankExperience({ content }: Props) {
  return (
    <main>
      <OptimizelyComposition
        nodes={content.composition?.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

### `OptimizelyComposition` contract

| Prop | Type | Purpose |
|---|---|---|
| `nodes` | `ExperienceNode[]` | Flat list from `content.composition.nodes` |
| `ComponentWrapper` | `({children, node}: ComponentContainerProps) => JSX.Element` | Optional. Wraps each top-level component node. Spread `{...pa(node)}` on the outermost element so editors can click-to-edit. |

Each node is either a component node (has `component` + metadata) or a structure node (row/column/section). `OptimizelyComposition` recursively renders both, delegating component resolution to `OptimizelyComponent` (which reads `initReactComponentRegistry`).

## BlankSection — canonical grid wrapper

```tsx
// src/components/experiences/BlankSection.tsx (abbreviated)
import { BlankSectionContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  OptimizelyGridSection,
  StructureContainerProps,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';

function Row({ children, node, displaySettings }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="vb:row flex flex-row gap-6" {...pa(node)}>{children}</div>
  );
}

function Column({ children, node, displaySettings }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="vb:col flex-1 flex flex-col gap-4 min-w-0" {...pa(node)}>{children}</div>
  );
}

type Props = { content: ContentProps<typeof BlankSectionContentType> };

export default function BlankSection({ content }: Props) {
  const { pa } = getPreviewUtils(content);
  return (
    <section className="vb:grid relative w-full py-12 px-4 overflow-visible" {...pa(content)}>
      <div className="max-w-7xl mx-auto w-full">
        <OptimizelyGridSection nodes={content.nodes} row={Row} column={Column} />
      </div>
    </section>
  );
}
```

### `OptimizelyGridSection` contract

| Prop | Type | Purpose |
|---|---|---|
| `nodes` | `ExperienceNode[]` | From `content.nodes` (NOT `content.composition.nodes` — sections use a flatter shape) |
| `row` | `(props: StructureContainerProps) => JSX.Element` | Optional. Wraps each row. |
| `column` | `(props: StructureContainerProps) => JSX.Element` | Optional. Wraps each column. |

Defaults to SDK-provided row/column wrappers if you omit the props — but always provide your own so you can apply layout styling and attach preview attributes (`{...pa(node)}`).

### `StructureContainerProps`

```ts
type StructureContainerProps = {
  children: React.ReactNode;
  node: ExperienceStructureNode;             // { key, displayTemplateKey, ... }
  displaySettings?: Record<string, unknown>; // resolved from nodeType: 'row' | 'column' display templates
};
```

`displaySettings` is populated when a `displayTemplate({ nodeType: 'row' | 'column', settings: {...} })` matches the structure node and the editor has selected variant settings. Read it in your wrapper to apply editor-driven styling:

```tsx
function Row({ children, node, displaySettings }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  const gap = displaySettings?.columnGap ?? 'medium';
  const align = displaySettings?.verticalAlignment ?? 'start';
  return (
    <div
      className={cn('vb:row flex flex-row', gapClass[gap], alignClass[align])}
      {...pa(node)}
    >
      {children}
    </div>
  );
}
```

Schema for row/column display templates lives in the content-types skill (`references/standard-types.md` row/column section).

### The `vb:` class prefix

Visual Builder expects:
- `vb:grid` on the outer `<section>`
- `vb:row` on each row
- `vb:col` on each column

These are **marker classes** the Visual Builder UI looks for to identify layout regions. Not Tailwind, not optional. If they're missing, the editor UI can't position drop zones correctly — section content renders fine in the public site but is uneditable in the CMS preview.

## `getPreviewUtils(target)` — `pa()` and `src()`

```ts
const { pa, src } = getPreviewUtils(target);
```

### `pa(target?)` → click-to-edit attributes

```tsx
<h1 {...pa('title')}>{content.title}</h1>          // property-scoped edit
<div {...pa(node)}>{children}</div>                 // node-scoped edit
<div {...pa(content)}>{children}</div>              // content-scoped edit
<div {...pa({ key: 'customId' })}>                  // custom key form
```

- In **preview/edit mode**: returns `data-epi-*` attributes (e.g. `{ 'data-epi-property-name': 'title' }`).
- In **published mode**: returns `{}` — the spread is a no-op.

Safe to spread on any element regardless of mode.

### `src(input)` → preview-aware URL

```tsx
const { src } = getPreviewUtils(content);
<img src={src(content.image)} alt="" />
```

In preview mode, appends the preview token (from context) to image URLs so unpublished asset versions resolve. In published mode, returns the URL unchanged. Omit this and draft images won't load when an editor previews a page with newly-uploaded media.

Works with `next/image` too:
```tsx
<Image src={src(content.image)!} alt={getAlt(content.image, '')} fill />
```

(The `!` non-null assertion is acceptable here — you've already checked `content.image` exists; `src()` returns `string | undefined`.)

## `data-epi-edit` for plain blocks (alternative to `pa`)

For non-Visual-Builder blocks where editing happens through the form-based property editor rather than click-to-edit, you can annotate editable text directly:

```tsx
<h1 data-epi-edit="title">{title}</h1>
<p  data-epi-edit="subtitle">{subtitle}</p>
```

The attribute value is the property key from the content-type schema. Lower-level than `pa()` — use `pa()` in experience/section wrappers (where the target is a node, not a property), and use `pa('propertyName')` or `data-epi-edit="propertyName"` in regular blocks (both work; `pa` is preferred since it's a no-op in published mode).

### Exact-match requirement — common silent failure

The attribute value is matched character-for-character against the schema property keys:

```tsx
// contentType declares { title, subtitle }
<h1 data-epi-edit="title">{title}</h1>          // ✓ click-to-edit works
<p  data-epi-edit="sub-title">{subtitle}</p>   // ✗ kebab mismatch — silently disabled
<p  data-epi-edit="Subtitle">{subtitle}</p>    // ✗ case mismatch — silently disabled
```

Only the broken field loses click-to-edit; everything else still works. The editor sees no error, just no inline-edit affordance on that specific field. When troubleshooting "I can edit X but not Y in preview", check the attribute value first.

## `compositionBehaviors` — letting a block be a section/element

If a block should be placeable as a top-level Visual Builder node (not just nested inside a section), mark it:

```ts
export const HeroBlockCT = contentType({
  key: 'HeroBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: { /* ... */ },
});
```

Valid values:
- `'sectionEnabled'` — block can appear as a section in an experience
- `'elementEnabled'` — block can appear as an inline element inside a section

Both can coexist (`['sectionEnabled', 'elementEnabled']`). When using `elementEnabled`, the schema must respect element property restrictions (no `content`/`component`/`json` properties, no arrays of content) — see the content-types skill.

## Display templates on composition nodes

When a content type has multiple display templates, the editor picks one per placement. At render time, the SDK passes `displaySettings` as the component's second prop:

```tsx
// Component receives content + displaySettings
export default function ProfileBlock({
  content,
  displaySettings,
}: {
  content: ContentProps<typeof ProfileBlockCT>;
  displaySettings?: ContentProps<typeof ProfileBlockDisplayTemplate>;
}) {
  const colorScheme = displaySettings?.colorScheme ?? 'default';
  return <section className={backgroundVariants({ colorScheme })}>...</section>;
}
```

Register the template via `initDisplayTemplateRegistry([ProfileBlockDisplayTemplate])` in `src/optimizely.ts`. See the content-types skill for template definition syntax and component-variant registration patterns (`{ default, tags }` vs `'Key:Tag'`).

### Top-level experiences get no `displaySettings` prop

The "second prop" above only reaches **nested** composition nodes. `OptimizelyComposition` and `OptimizelyGridSection` parse each child node's raw `displaySettings` and hand the result to `OptimizelyComponent`. But a **top-level experience** is rendered by the catch-all (and `/preview`) route as `<OptimizelyComponent content={content} />` with no `displaySettings` argument — and `OptimizelyComponent` only forwards what it was given. It never parses the experience's own settings.

So an experience component's `displaySettings` prop is **always `undefined`** — including `BlankExperience` and any `_experience` type that has a display template. The experience examples above destructure only `{ content }` for this reason.

The experience's own settings live on the **root composition node** as a raw `{ key, value }[]` array. Read and parse them inside the component:

```tsx
import { ContentProps, DisplayTemplates } from '@optimizely/cms-sdk';

export default function LandingPageExperience({ content, displaySettings }: Props) {
  // Top-level experiences receive no displaySettings prop — parse the
  // experience's own settings off the root composition node.
  const settings = (displaySettings ??
    DisplayTemplates.parseDisplaySettings(content.composition?.displaySettings)) as
    | ContentProps<typeof LandingPageExperienceDisplayTemplate>
    | undefined;

  const surface = settings?.surface ?? 'light';
  // ...
}
```

`DisplayTemplates.parseDisplaySettings` (exported from `@optimizely/cms-sdk`) converts the `{ key, value }[]` array into a keyed object and coerces `'true'`/`'false'` strings to booleans. Symptom when missed: experience-level display-template settings (background, header style, theme toggles, …) silently do nothing.

## Debugging Visual Builder rendering

| Symptom | Cause |
|---|---|
| Nodes render but can't be edited | Missing `{...pa(node)}` on the wrapper element |
| Drop zones don't appear in the editor | Missing `vb:grid` / `vb:row` / `vb:col` classes |
| "Component not found" in render | Content type referenced by the composition isn't in `initReactComponentRegistry.resolver` |
| Layout styles applied twice / conflicting | Probably wrapped `<BlankExperience>` AND a section inside another layout container — Visual Builder already handles nesting |
| Images load in published but not in preview | Missing `src()` wrapping — use `getPreviewUtils(content).src(content.image)` not `content.image.url.default` |
| `displaySettings` prop `undefined` in an **experience** component | Expected — top-level experiences are never passed it. Parse `content.composition.displaySettings` yourself (see "Top-level experiences get no `displaySettings` prop") |
| `displaySettings` `undefined` in a **block/section** component | No display template registered for the type, or the editor hasn't picked one (defaults to undefined) |
| Section content renders empty in preview | `BlankSectionContentType` not in `initContentTypeRegistry` — SDK can't resolve the section type |

## Where this pattern lives in the SDK

- `OptimizelyComposition`, `OptimizelyGridSection`, `getPreviewUtils`, `ComponentContainerProps`, `StructureContainerProps` — `@optimizely/cms-sdk/react/server`
- `BlankExperienceContentType`, `BlankSectionContentType` — `@optimizely/cms-sdk`
- Official reference: <https://github.com/episerver/content-js-sdk/blob/main/docs/8-experience.md>
