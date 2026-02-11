# Composition Patterns

Advanced composition patterns for Optimizely CMS content types.

## CompositionBehaviors

Make components work in Visual Builder:

```typescript
export const CardBlockCT = contentType({
  key: 'CardBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled', 'elementEnabled'],  // Both!
  properties: { /* ... */ },
});
```

**Options:**
- `'sectionEnabled'` - Works as section
- `'elementEnabled'` - Works as element
- Both - Maximum flexibility

## MayContainTypes

Control which types can be children:

```typescript
export const BlogPageCT = contentType({
  key: 'BlogPage',
  baseType: '_page',
  mayContainTypes: [
    ArticleCT,
    '_page',     // All pages
    '_self',     // Same type
    '*',         // All types (wildcard)
  ],
});
```

## Nested Content

### Single Content Area

```typescript
properties: {
  heroSection: {
    type: 'content',
    displayName: 'Hero Section',
    allowedTypes: ['HeroBlock'],
  },
}
```

### Content Array

```typescript
properties: {
  contentSections: {
    type: 'array',
    displayName: 'Content Sections',
    items: { 
      type: 'content',
      allowedTypes: ['HeroBlock', 'CardBlock'],
    },
    maxItems: 10,
  },
}
```

### Component Type (Strongly Typed)

```typescript
import { HeroBlockCT } from './HeroBlock';

properties: {
  hero: {
    type: 'component',
    contentType: HeroBlockCT,  // Specific type
    displayName: 'Hero',
  },
}
```

## Accordion/Tab Pattern

```typescript
// Container
export const AccordionCT = contentType({
  key: 'Accordion',
  baseType: '_component',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'component',
        contentType: AccordionItemCT,
      },
    },
  },
});

// Item
export const AccordionItemCT = contentType({
  key: 'AccordionItem',
  baseType: '_component',
  properties: {
    heading: { type: 'string', required: true },
    content: { type: 'richText', required: true },
  },
});
```

## AllowedTypes & RestrictedTypes

```typescript
featuredImage: {
  type: 'contentReference',
  allowedTypes: ['_image'],  // Whitelist
}

relatedContent: {
  type: 'content',
  restrictedTypes: ['_folder'],  // Blacklist
}
```

**Options:**
- Specific types: `[ArticleCT]`
- Base types: `['_page', '_component']`
- Self: `['_self']`
- All: `['*']`

## Experience with Sections, Rows, and Columns

Visual Builder experiences use a grid system with sections containing rows and columns. Here's how to style them properly:

### Experience Page Component

```typescript
// LandingPage.tsx
import { contentType, Infer } from "@optimizely/cms-sdk";
import {
  ComponentContainerProps,
  OptimizelyExperience,
  getPreviewUtils,
} from "@optimizely/cms-sdk/react/server";

export const LandingPageContentType = contentType({
  key: "LandingPage",
  baseType: "_experience",
  displayName: "Landing Page",
  properties: {
    // Add custom properties like SEO settings
  },
});

type Props = {
  opti: Infer<typeof LandingPageContentType>;
};

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div {...pa(node)}>{children}</div>;
}

export default function LandingPage({ opti }: Props) {
  return (
    <main className="landing-page min-h-screen bg-linear-to-b from-gray-50 to-white">
      <OptimizelyExperience
        nodes={opti.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

### Section Component (BlankSection)

Sections are full-width containers that hold rows and columns:

```typescript
// BlankSection.tsx
import { BlankSectionContentType, Infer } from '@optimizely/cms-sdk';
import {
  OptimizelyGridSection,
  getPreviewUtils,
  StructureContainerProps,
} from '@optimizely/cms-sdk/react/server';

type BlankSectionProps = {
  opti: Infer<typeof BlankSectionContentType>;
};

export default function BlankSection({ opti }: BlankSectionProps) {
  const { pa } = getPreviewUtils(opti)
  return (
    <section
      className="vb:grid relative w-full py-12 px-4 md:px-6 lg:px-8 overflow-visible"
      {...pa(opti)}
    >
      <div className="max-w-7xl mx-auto w-full">
        <OptimizelyGridSection nodes={opti.nodes} row={Row} column={Column} />
      </div>
    </section>
  )
}

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node)
  return (
    <div
      className="vb:row flex flex-row gap-6 lg:gap-8 mb-6 last:mb-0"
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
      className="vb:col flex-1 flex flex-col gap-4 min-w-0"
      {...pa(node)}
    >
      {children}
    </div>
  )
}
```

**Key styling patterns:**
- **Section**: Full-width with responsive padding and centered max-width container
- **Row**: Flex row with gaps between columns, stacks multiple rows vertically
- **Column**: Equal-width columns (`flex-1`) that contain elements, `min-w-0` prevents overflow
- **Visual Builder classes**: `vb:grid`, `vb:row`, `vb:col` for editor integration

### Preview Mode CSS

Add to `globals.css` to prevent layout shifts from Visual Builder overlays:

```css
/* Optimizely Visual Builder Preview Styles */
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

## Best Practices

1. Use `compositionBehaviors` for Visual Builder
2. Control with `allowedTypes`
3. Use `component` type for strong typing
4. Use `content` type for flexibility
5. Limit array sizes with `maxItems`
6. Don't nest too deep (2-3 levels max)
7. Use `mayContainTypes` with `'*'` cautiously
8. For experiences, provide proper Row/Column components to `OptimizelyGridSection`
9. Use `flex-1` on columns for equal-width distribution
10. Add `overflow-visible` to sections to allow Visual Builder overlays
