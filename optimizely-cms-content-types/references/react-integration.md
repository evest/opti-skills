# React Integration Reference

The SDK provides React components for rendering CMS content with Visual Builder support. First-class support for React 19 and Next.js App Router.

## Exports

### Server Components (`@optimizely/cms-sdk/react/server`)

```typescript
import {
  initReactComponentRegistry,
  OptimizelyComponent,
  OptimizelyComposition,
  OptimizelyGridSection,
  getPreviewUtils,
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

## Component Registry

Register your React components so the SDK can resolve them from content types:

```typescript
// src/optimizely.ts
import { initContentTypeRegistry, initDisplayTemplateRegistry, BlankExperienceContentType, BlankSectionContentType } from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

// Register content types
initContentTypeRegistry([
  BlankExperienceContentType,
  BlankSectionContentType,
  ArticlePageCT,
  HeroBlockCT,
  ButtonElementCT,
  // ... all content types
]);

// Register display templates
initDisplayTemplateRegistry([
  HeroDefaultTemplate,
  ButtonDisplayTemplate,
  // ... all display templates
]);

// Map content types to React components
initReactComponentRegistry({
  resolver: {
    // Simple mapping: content type key → component
    'ArticlePage': ArticlePage,
    'HeroBlock': HeroBlock,
    'ButtonElement': ButtonElement,
    'BlankExperience': BlankExperience,
    'BlankSection': BlankSection,

    // Tagged variants using 'ContentType:Tag' syntax
    'HeroBlock:Centered': CenteredHeroBlock,

    // Or with default + tags object
    'CardBlock': {
      default: DefaultCardBlock,
      tags: { Christmas: ChristmasCardBlock },
    },
  },
});
```

Import this file in your root layout:
```typescript
// src/app/layout.tsx
import '@/optimizely';
```

### Dynamic Resolver

For advanced cases (lazy loading, conditional rendering):

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

// In a page component
<OptimizelyComponent content={contentData} />

// With display settings
<OptimizelyComponent content={contentData} displaySettings={{ variant: 'outlined' }} />
```

**Props:**
- `content` — Content data from GraphClient (must have `__typename`)
- `displaySettings?` — Record of display setting values

## OptimizelyComposition

Renders Visual Builder experience nodes (sections, rows, columns, elements).

```typescript
import { OptimizelyComposition, type ComponentContainerProps } from '@optimizely/cms-sdk/react/server';

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  return <div data-type={node.type}>{children}</div>;
}

export default function LandingPage({ opti }) {
  return (
    <main>
      <OptimizelyComposition
        nodes={opti.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

**Props:**
- `nodes: ExperienceNode[]` — Composition nodes from the experience
- `ComponentWrapper?` — Optional wrapper for component nodes

## OptimizelyGridSection

Renders the grid layout (rows + columns) within a section.

```typescript
import {
  OptimizelyGridSection,
  getPreviewUtils,
  type StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';

export default function BlankSection({ opti }) {
  const { pa } = getPreviewUtils(opti);

  return (
    <section className="w-full py-12 px-4" {...pa(opti)}>
      <div className="max-w-7xl mx-auto">
        <OptimizelyGridSection nodes={opti.nodes} row={Row} column={Column} />
      </div>
    </section>
  );
}

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="flex flex-row gap-6" {...pa(node)}>
      {children}
    </div>
  );
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return (
    <div className="flex-1 flex flex-col gap-4 min-w-0" {...pa(node)}>
      {children}
    </div>
  );
}
```

**Props:**
- `nodes: ExperienceNode[]` — Grid nodes (rows, columns, components)
- `row?` — Custom row container component
- `column?` — Custom column container component

## getPreviewUtils

Returns context-aware preview helpers for Visual Builder on-page editing.

```typescript
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';

export default function HeroBlock({ opti }) {
  const { pa, src } = getPreviewUtils(opti);

  return (
    <div {...pa(opti)}>
      <h1 {...pa('title')}>{opti.title}</h1>
      <img src={src(opti.backgroundImage)} alt="" />
    </div>
  );
}
```

### `pa(property?)`

Returns `data-epi-*` attributes for on-page editing overlays.

```typescript
const { pa } = getPreviewUtils(opti);

// For the whole component (block-level)
<div {...pa(opti)}>

// For a specific property
<h1 {...pa('title')}>{opti.title}</h1>

// With key object
<p {...pa({ key: 'description' })}>{opti.description}</p>
```

### `src(input)`

Appends preview token to image URLs for preview mode. Returns `string | undefined`.

```typescript
const { src } = getPreviewUtils(opti);

<img src={src(opti.heroImage)} alt="" />
// In preview: adds ?preview_token=xxx
// In production: returns the URL as-is
```

## PreviewComponent (Client)

Client component that listens for CMS content saved events and refreshes the preview.

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

## RichText Component

Renders rich text content from the CMS.

```typescript
import { RichText } from '@optimizely/cms-sdk/react/richText';

export default function ArticlePage({ opti }) {
  return (
    <article>
      <RichText content={opti.body?.json} className="prose" />
    </article>
  );
}
```

## Complete Example: Experience Page

```typescript
// src/components/LandingPage.tsx
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

type Props = { opti: ContentProps<typeof LandingPageCT> };

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div {...pa(node)}>{children}</div>;
}

export default function LandingPage({ opti }: Props) {
  return (
    <main>
      <OptimizelyComposition
        nodes={opti.composition.nodes ?? []}
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

// From react/server
import type {
  StructureContainerProps,
  ComponentContainerProps,
} from '@optimizely/cms-sdk/react/server';
```
