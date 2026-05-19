# Visual Builder Registry Setup

This page covers the content-type-side of Visual Builder setup: registering the built-in `BlankExperience` and `BlankSection` types so the SDK can resolve them.

> The preview route itself (`/preview/page.tsx`, `withAppContext`, `PreviewComponent`, `communicationinjector.js`, env vars) is covered by the **`optimizely-cms-nextjs` skill**. This page intentionally does not duplicate that wiring.

## 1. Register the built-in types

The SDK ships `BlankExperienceContentType` and `BlankSectionContentType` — the default Visual Builder experience and section. They are **not** auto-registered; you must include them in `initContentTypeRegistry` if your CMS uses them.

```typescript
// src/optimizely.ts (imported from app/layout.tsx)
import {
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

import * as contentTypes from '@/content-types';
import * as displayTemplates from '@/display-templates';
import * as components from '@/components';

initContentTypeRegistry([
  BlankExperienceContentType,   // Visual Builder experiences
  BlankSectionContentType,      // Visual Builder sections
  ...Object.values(contentTypes),
]);

initDisplayTemplateRegistry([...Object.values(displayTemplates)]);

initReactComponentRegistry({
  resolver: {
    BlankExperience: components.BlankExperience,
    BlankSection: components.BlankSection,
    // ... your own components
  },
});
```

If you omit either built-in type but Visual Builder content references it, you'll see a runtime error like:

```
Content type "BlankExperience" not included in the registry.
Ensure that you called "initContentTypeRegistry()" with it before fetching content.
```

## 2. Provide React components for the built-in types

Even though the content types are built into the SDK, you supply your own React components for them. Minimum implementations:

**`src/components/experiences/BlankExperience.tsx`**

```tsx
import { BlankExperienceContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  OptimizelyComposition,
  getPreviewUtils,
  type ComponentContainerProps,
} from '@optimizely/cms-sdk/react/server';

type Props = {
  content: ContentProps<typeof BlankExperienceContentType>;
};

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div {...pa(node)}>{children}</div>;
}

export default function BlankExperience({ content }: Props) {
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

**`src/components/experiences/BlankSection.tsx`**

```tsx
import { BlankSectionContentType, ContentProps } from '@optimizely/cms-sdk';
import {
  OptimizelyGridSection,
  getPreviewUtils,
  type StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';

type Props = {
  content: ContentProps<typeof BlankSectionContentType>;
};

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="flex flex-row gap-6" {...pa(node)}>{children}</div>;
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="flex-1 flex flex-col gap-4 min-w-0" {...pa(node)}>{children}</div>;
}

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

`StructureContainerProps` provides:
- `children` — the nested content to render
- `node` — the structure node (`key`, `displayTemplateKey`, `displaySettings`)
- `displaySettings` — applied row/column display template settings (when `nodeType: 'row'` or `'column'` templates exist)

See `references/composition-patterns.md` for richer row/column styling and `references/standard-types.md` for `nodeType: 'row'` / `nodeType: 'column'` display templates.

## 3. Preview-mode CSS (recommended)

Add to your global stylesheet so Visual Builder overlays render correctly:

```css
.vb\:grid,
.vb\:row,
.vb\:col {
  position: relative;
}

body[data-epi-edit-mode] {
  overflow-x: hidden;
}

[data-epi-block-id],
[data-epi-property-name] {
  position: relative;
}
```

## 4. The preview route

For the `/preview/page.tsx` route, the `withAppContext` HOC, the communication injector, and required env vars — see the **`optimizely-cms-nextjs` skill**. That's where the Next.js integration details live.

Quick mental model: the preview route wraps with `withAppContext(Page)`, calls `client.getPreviewContent(searchParams as PreviewParams)`, renders `<PreviewComponent />` (client component for live updates) plus `<OptimizelyComponent content={response} />`, and loads `communicationinjector.js` via `next/script`.
