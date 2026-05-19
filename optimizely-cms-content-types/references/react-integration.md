# React Integration Reference (v2)

The SDK provides React helpers for rendering CMS content with Visual Builder support. First-class support for React 19 and Next.js App Router.

> This page covers the **component-pattern API** that content-type developers consume. Full Next.js wiring (root layout, preview route, ISR, middleware, image loaders) lives in the `optimizely-cms-nextjs` skill.

## Exports

### Server Components (`@optimizely/cms-sdk/react/server`)

```typescript
import {
  initReactComponentRegistry,
  OptimizelyComponent,
  OptimizelyComposition,
  OptimizelyGridSection,
  getPreviewUtils,
  withAppContext,
  getContext,
  getContextData,
  setContext,
  type ComponentContainerProps,
  type StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';
```

### Client Components (`@optimizely/cms-sdk/react/client`)

```typescript
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
```

### Rich Text (`@optimizely/cms-sdk/react/richText`)

```typescript
import { RichText } from '@optimizely/cms-sdk/react/richText';
```

See `references/rich-text.md` for the RichText API surface.

## Component Registry

Register your React components so the SDK can resolve them from content types:

```typescript
// src/optimizely.ts
import {
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

initContentTypeRegistry([
  BlankExperienceContentType,
  BlankSectionContentType,
  ArticlePageCT,
  HeroBlockCT,
  ButtonElementCT,
  // ... all content types
]);

initDisplayTemplateRegistry([
  HeroDefaultTemplate,
  ButtonDisplayTemplate,
  // ... all display templates
]);

initReactComponentRegistry({
  resolver: {
    // Simple mapping: content type key → component
    ArticlePage,
    HeroBlock,
    ButtonElement,
    BlankExperience,
    BlankSection,

    // Component variants (two equivalent patterns)
    // Pattern A — object form (recommended for many variants)
    CardBlock: {
      default: DefaultCardBlock,
      tags: {
        Christmas: ChristmasCardBlock,
        Summer: SummerCardBlock,
      },
    },

    // Pattern B — colon syntax (concise for one or two)
    'HeroBlock:Centered': CenteredHeroBlock,
  },
});
```

Import this file in your root layout:
```typescript
// src/app/layout.tsx
import '@/optimizely';
```

### Resolver dispatch order

When the SDK looks up a component for content of type `X` with display template `tag: 'Y'`:
1. Try the tagged variant — `tags.Y` (object form) or `'X:Y'` (colon form).
2. Fall back to `default` (object form) or the bare `X` (colon form).

Both registration patterns are interchangeable — mix freely.

### Dynamic resolver

For lazy loading or runtime decisions:

```typescript
initReactComponentRegistry({
  resolver: (contentType, options) => {
    if (contentType === 'HeroBlock') {
      return options?.tag === 'Centered' ? CenteredHero : DefaultHero;
    }
    return undefined;
  },
});
```

## OptimizelyComponent

Renders a single content item by resolving it to the registered React component.

```typescript
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';

<OptimizelyComponent content={contentData} />

// With explicit display settings (rare; usually inferred from CMS)
<OptimizelyComponent content={contentData} displaySettings={{ variant: 'outlined' }} />
```

**Props:**
- `content` — content data from a GraphClient method (must include `__typename`)
- `displaySettings?` — record of display setting values

## OptimizelyComposition

Renders Visual Builder experience nodes (sections, rows, columns, components).

```typescript
import {
  OptimizelyComposition,
  getPreviewUtils,
  type ComponentContainerProps,
} from '@optimizely/cms-sdk/react/server';

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div {...pa(node)}>{children}</div>;
}

export default function LandingPage({ content }) {
  return (
    <main>
      <OptimizelyComposition
        nodes={content.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

**Props:**
- `nodes: ExperienceNode[]` — composition nodes from the experience
- `ComponentWrapper?` — optional wrapper around each component node (this is where you attach preview attributes for click-to-edit)

## OptimizelyGridSection

Renders the grid layout (rows + columns) inside a section.

```typescript
import {
  OptimizelyGridSection,
  getPreviewUtils,
  type StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';

export default function BlankSection({ content }) {
  const { pa } = getPreviewUtils(content);

  return (
    <section className="w-full py-12 px-4" {...pa(content)}>
      <div className="max-w-7xl mx-auto">
        <OptimizelyGridSection nodes={content.nodes} row={Row} column={Column} />
      </div>
    </section>
  );
}

function Row({ children, node, displaySettings }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="flex flex-row gap-6" {...pa(node)}>
      {children}
    </div>
  );
}

function Column({ children, node, displaySettings }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="flex-1 flex flex-col gap-4 min-w-0" {...pa(node)}>
      {children}
    </div>
  );
}
```

**Props:**
- `nodes: ExperienceNode[]` — grid nodes (rows, columns, components)
- `row?` — custom row container component
- `column?` — custom column container component

`StructureContainerProps` includes:
- `children` — rendered child content
- `node` — the structure node (`key`, `displayTemplateKey`, etc.)
- `displaySettings` — display settings from `nodeType: 'row'` / `'column'` templates (when defined)

You can read `displaySettings` to apply row/column-level styling (gaps, padding, alignment) driven by editor choices in the CMS. See `references/composition-patterns.md` for a worked example.

## getPreviewUtils

Returns context-aware preview helpers for Visual Builder on-page editing.

```typescript
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';

export default function HeroBlock({ content }) {
  const { pa, src } = getPreviewUtils(content);

  return (
    <div {...pa(content)}>
      <h1 {...pa('title')}>{content.title}</h1>
      <img src={src(content.backgroundImage)} alt="" />
    </div>
  );
}
```

### `pa(property?)`

Returns `data-epi-*` attributes for on-page editing overlays.

```typescript
const { pa } = getPreviewUtils(content);

// For the whole component (block-level overlay)
<div {...pa(content)}>

// For a specific property
<h1 {...pa('title')}>{content.title}</h1>

// With a key object (rarely needed)
<p {...pa({ key: 'description' })}>{content.description}</p>
```

### `src(input)`

Resolves a content-reference URL. In preview mode, automatically appends the active preview token. Returns `string | undefined`.

```typescript
const { src } = getPreviewUtils(content);

<img src={src(content.heroImage)} alt="" />
// In preview: '…?preview_token=xxx'
// In production: the URL as-is
```

## withAppContext, getContext, getContextData, setContext

`withAppContext` is a server-side HOC that initialises request-scoped context storage. `getPreviewContent` and other SDK calls populate it with `preview_token`, `locale`, `key`, `version`, `mode`.

```typescript
import {
  withAppContext,
  getContextData,
} from '@optimizely/cms-sdk/react/server';

function Page({ searchParams }: Props) {
  return /* ... */;
}

export default withAppContext(Page);
```

Inside any nested component:

```typescript
import { getContextData } from '@optimizely/cms-sdk/react/server';

export function PreviewBanner() {
  const preview_token = getContextData('preview_token');
  const locale = getContextData('locale');

  if (!preview_token) return null;
  return <div>Preview mode — locale: {locale ?? 'default'}</div>;
}
```

`setContext({ … })` lets you push your own request-scoped data into the context (useful inside catch-all pages to expose the resolved content metadata to nested components).

Detailed preview-route wiring, error handling, and locale bridging belong to the `optimizely-cms-nextjs` skill.

## PreviewComponent (Client)

Client component that listens for CMS content-saved events and refreshes the preview.

```typescript
// Only use in preview routes
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';

export default function PreviewPage() {
  return (
    <div>
      <PreviewComponent />
      {/* ... rest of preview content */}
    </div>
  );
}
```

## RichText (quick reference)

```typescript
import { RichText } from '@optimizely/cms-sdk/react/richText';

export default function ArticlePage({ content }) {
  return (
    <article className="prose">
      <RichText content={content.body?.json} />
    </article>
  );
}
```

`RichText` does not accept `className` — wrap it. Full reference in `references/rich-text.md`.

## Complete Example: Experience Page

```typescript
import { contentType, ContentProps, BlankExperienceContentType } from '@optimizely/cms-sdk';
import {
  OptimizelyComposition,
  getPreviewUtils,
  type ComponentContainerProps,
} from '@optimizely/cms-sdk/react/server';

export const LandingPageCT = contentType({
  key: 'LandingPage',
  baseType: '_experience',
  displayName: 'Landing Page',
  properties: {},
});

type Props = { content: ContentProps<typeof LandingPageCT> };

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div {...pa(node)}>{children}</div>;
}

export default function LandingPage({ content }: Props) {
  return (
    <main>
      <OptimizelyComposition
        nodes={content.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

## TypeScript Types

Key types exported from the SDK:

```typescript
import type {
  ExperienceNode,
  ExperienceStructureNode,
  ExperienceComponentNode,
  ExperienceCompositionNode,
  DisplaySettingsType,
  InferredUrl,
  InferredContentReference,
  ContentReferenceItem,
} from '@optimizely/cms-sdk';

import type {
  StructureContainerProps,
  ComponentContainerProps,
} from '@optimizely/cms-sdk/react/server';
```
