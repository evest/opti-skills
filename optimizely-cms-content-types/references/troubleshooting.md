# Troubleshooting Guide

Common issues and solutions when working with Optimizely CMS content types and React components.

## CMS Sync Errors

### "Cannot read properties of undefined (reading 'map')"

**Error**: When running `npx optimizely-cms-cli config push`, you get: `TypeError: Cannot read properties of undefined (reading 'map')`

**Cause**: The `optimizely.config.mjs` file is incorrectly structured. The config must use `components` with **file paths as strings**, not directly imported content type objects.

**❌ Wrong - importing objects directly:**
```javascript
import { buildConfig } from '@optimizely/cms-sdk';
import { ButtonElementCT } from './src/cms/content-types/elements/ButtonElement.ts';
import { HeroBlockCT, HeroDisplayTemplate } from './src/cms/content-types/blocks/HeroBlock.ts';

export default buildConfig({
  contentTypes: [ButtonElementCT, HeroBlockCT],  // ❌ WRONG!
  displayTemplates: [HeroDisplayTemplate],       // ❌ WRONG!
  propertyGroups: [
    { key: 'content', displayName: 'Content', sortOrder: 1 },
  ],
});
```

**✅ Correct - use file paths:**
```javascript
import { buildConfig } from '@optimizely/cms-sdk';

export default buildConfig({
  components: [
    './src/cms/content-types/elements/ButtonElement.ts',
    './src/cms/content-types/blocks/HeroBlock.ts',
  ],
  propertyGroups: [
    { key: 'content', displayName: 'Content', sortOrder: 1 },
  ],
});
```

**Key points:**
- Use `components` array with file path strings (not imports)
- The CLI automatically discovers `contentType()` and `displayTemplate()` exports
- Do NOT use `contentTypes` or `displayTemplates` arrays with imported objects
- Property groups are still defined inline (not as file paths)

---

### "The base type '_element' is not supported"

**Error**: When pushing config to CMS, you get an error: `The base type '_element' is not supported.`

**Cause**: There is no `_element` base type in Optimizely CMS. Elements are actually `_component` types with the `elementEnabled` composition behavior.

**❌ Wrong:**
```typescript
export const TextElementCT = contentType({
  key: 'TextElement',
  displayName: 'Text Element',
  baseType: '_element',  // ❌ This base type does not exist!
  properties: {
    text: { type: 'string', displayName: 'Text' },
  },
});
```

**✅ Correct:**
```typescript
export const TextElementCT = contentType({
  key: 'TextElement',
  displayName: 'Text Element',
  baseType: '_component',  // ✅ Use _component
  compositionBehaviors: ['elementEnabled'],  // ✅ Add elementEnabled behavior
  properties: {
    text: { type: 'string', displayName: 'Text' },
  },
});
```

**Key points:**
- Elements use `baseType: '_component'`
- Add `compositionBehaviors: ['elementEnabled']` to make it an element
- You can also add `'sectionEnabled'` if you want the component to work as both

---

### "The property 'X' is not allowed when content type has ElementEnabled"

**Error**: When pushing config to CMS, you get an error about array properties not being allowed with `elementEnabled`.

**Cause**: Optimizely CMS restricts content types with `compositionBehaviors: ["elementEnabled"]` from having certain complex property types. Elements are meant to be simple, atomic components, not containers.

**FORBIDDEN property types with `elementEnabled`:**
1. ❌ Arrays with content: `type: "array"` with `items: { type: "content" }`
2. ❌ Content properties: `type: "content"`
3. ❌ Component properties: `type: "component"`
4. ❌ JSON properties: `type: "json"`

**ALLOWED property types with `elementEnabled`:**
- ✅ Simple types: `string`, `boolean`, `integer`, `float`, `dateTime`, `url`, `richText`
- ✅ Content references: `type: "contentReference"` (for images, media)
- ✅ Arrays of simple types: `type: "array"` with `items: { type: "string" }` etc.

**Solution options:**

1. **Remove elementEnabled** - If the component needs to contain other content, keep only `sectionEnabled`:
   ```typescript
   compositionBehaviors: ["sectionEnabled"],  // Remove "elementEnabled"
   ```

2. **Remove the array property** - If you want to keep it as an element, remove array properties with content items

3. **Use JSON instead** - For simple data arrays (not content references), use `type: "json"`:
   ```typescript
   // ❌ Not allowed with elementEnabled
   items: {
     type: "array",
     items: { type: "content", allowedTypes: [ItemType] }
   }

   // ✅ Allowed - simple data
   items: {
     type: "json",
     displayName: "Items",
     description: "Array of item data"
   }
   ```

**Example:**

```typescript
// ❌ This will fail when syncing to CMS
export const AccordionBlockType = contentType({
  key: "AccordionBlock",
  baseType: "_component",
  compositionBehaviors: ["elementEnabled", "sectionEnabled"],  // Has elementEnabled
  properties: {
    items: {  // Array of content - NOT ALLOWED!
      type: "array",
      items: {
        type: "content",
        allowedTypes: [AccordionItemType],
      },
    },
  },
});

// ✅ Fixed - removed elementEnabled
export const AccordionBlockType = contentType({
  key: "AccordionBlock",
  baseType: "_component",
  compositionBehaviors: ["sectionEnabled"],  // Only sectionEnabled
  properties: {
    items: {  // Now allowed
      type: "array",
      items: {
        type: "content",
        allowedTypes: [AccordionItemType],
      },
    },
  },
});
```

**Quick check**: Search your codebase for files with both `elementEnabled` and array properties:
```bash
grep -l "compositionBehaviors.*elementEnabled" src/components/*.tsx | xargs grep -l "items:"
```

## TypeScript Build Errors

### Module Import Errors

**❌ Error:** `Can't resolve '@optimizely/cms-sdk/react'`

**Cause:** Incorrect import path for React server utilities.

**✅ Correct import paths:**
```typescript
// ❌ Wrong
import { getPreviewUtils } from "@optimizely/cms-sdk/react";

// ✅ Correct
import { getPreviewUtils } from "@optimizely/cms-sdk/react/server";
import { RichText } from "@optimizely/cms-sdk/react/richText";
```

### Property Type Name Casing

**❌ Error:** `Type '"richtext"' is not assignable to type...`

**Cause:** Property type names must use exact camelCase.

**Common mistakes:**
```typescript
// ❌ Wrong
type: "richtext"  // lowercase
type: "RichText"  // PascalCase
type: "datetime"  // lowercase

// ✅ Correct
type: "richText"  // camelCase
type: "dateTime"  // camelCase
type: "contentReference"  // camelCase
```

### "Property X does not exist on type..."

This is the most common error when a property is used in your React component but not defined in the content type schema.

**Solution workflow:**
1. Check if the property is used in the component code
2. Add it to the `contentType()` definition with the correct type
3. For special types (URL, boolean, numeric), add proper type guards in the component
4. For JSON arrays, add TypeScript type definitions and cast appropriately
5. Register any new content types in `layout.tsx`

**Example:**
```typescript
// ❌ Error: Property 'cta' does not exist
export const CardBlockType = contentType({
  key: "CardBlock",
  baseType: "_component",
  properties: {
    heading: { type: "string", displayName: "Heading" },
    // Missing 'cta' property!
  },
});

// ✅ Fixed
import { CtaBlockType } from "./CtaBlock";

export const CardBlockType = contentType({
  key: "CardBlock",
  baseType: "_component",
  properties: {
    heading: { type: "string", displayName: "Heading" },
    cta: {
      type: "content",
      displayName: "Call to Action",
      description: "Optional CTA button",
      allowedTypes: [CtaBlockType],
    },
  },
});
```

## Display Template Errors

### "Object literal may only specify known properties, and 'type' does not exist..."

**❌ Error:** TypeScript error when defining display template settings.

**Cause:** Display template settings use a different structure than property definitions.

**❌ Wrong:**
```typescript
export const MyDisplayTemplate = displayTemplate({
  key: "MyDisplayTemplate",
  isDefault: true,
  settings: {
    alignment: {
      type: "select",  // ❌ 'type' is wrong
      label: "Alignment",
      options: [  // ❌ 'options' is wrong
        { value: "left", label: "Left" },
      ],
    },
  },
});
```

**✅ Correct:**
```typescript
export const MyDisplayTemplate = displayTemplate({
  key: "MyDisplayTemplate",
  isDefault: true,
  displayName: "My Display Template",
  baseType: "_component",
  settings: {
    alignment: {
      editor: "select",  // ✅ Use 'editor', not 'type'
      displayName: "Alignment",  // ✅ Use 'displayName', not 'label'
      sortOrder: 0,  // ✅ Required
      choices: {  // ✅ Use 'choices' object, not 'options' array
        left: {
          displayName: "Left",
          sortOrder: 0,
        },
        center: {
          displayName: "Center",
          sortOrder: 10,
        },
      },
    },
  },
});
```

**Key differences for display templates:**
- Use `editor: "select"` or `editor: "checkbox"` (not `type`)
- Use `displayName` (not `label`)
- Use `choices: { key: { displayName, sortOrder } }` (not `options: []`)
- Always include `sortOrder` for both settings and choices
- Include `displayName` and `baseType` at the template level

### RichText Component Props

**❌ Error:** `Property 'className' does not exist on type 'RichTextProps'`

**Cause:** The `RichText` component from the SDK doesn't accept a `className` prop.

**❌ Wrong:**
```typescript
<RichText content={opti.content?.json} className="prose" />
```

**✅ Correct - Wrap in a div:**
```typescript
<div className="prose prose-lg">
  <RichText content={opti.content?.json} />
</div>
```

### Styling for Light/Dark Mode

When using Tailwind's prose plugin, be careful with color modifiers:

**❌ Poor contrast in light mode:**
```typescript
<div className="prose prose-invert prose-lg">
  <RichText content={opti.content?.json} />
</div>
```

**✅ Good for light mode:**
```typescript
<div className="prose prose-lg">
  <RichText content={opti.content?.json} />
</div>
```

**✅ Adaptive (dark mode support):**
```typescript
<div className="prose prose-lg dark:prose-invert">
  <RichText content={opti.content?.json} />
</div>
```

## Property Type Issues

### Numeric Types

**❌ Wrong:**
```typescript
overlayOpacity: {
  type: "number",  // 'number' is not a valid type!
}
```

**✅ Correct:**
```typescript
overlayOpacity: {
  type: "integer",  // Use 'integer' or 'float'
  displayName: "Overlay Opacity",
  description: "Background overlay opacity (0-100)",
}
```

### Default Values Not Supported

The SDK does NOT support `default` values in property definitions.

**❌ Wrong:**
```typescript
allowMultiple: {
  type: "boolean",
  displayName: "Allow Multiple Open",
  default: false,  // This will cause a TypeScript error!
}
```

**✅ Correct:**
```typescript
// 1. Remove default from schema
allowMultiple: {
  type: "boolean",
  displayName: "Allow Multiple Open",
}

// 2. Handle default in component code
const allowMultiple = opti.allowMultiple ?? false;
// or
if (opti.allowMultiple === true) {
  // ...
}
```

### Arrays of Content

For arrays containing content items, use the nested structure:

```typescript
items: {
  type: "array",
  displayName: "Accordion Items",
  items: {
    type: "content",
    allowedTypes: [AccordionItemType],
  },
},
```

## Type Handling in Components

### InferredUrl Type

URL properties return `InferredUrl` objects, not strings. Access the string value via `.default`:

**❌ Wrong:**
```typescript
<Link href={opti.url}>...</Link>
// Error: Type 'InferredUrl' is not assignable to type 'Url'
```

**✅ Correct:**
```typescript
<Link href={opti.url?.default || "#"}>...</Link>
```

**For video/iframe src:**
```typescript
<iframe src={opti.embedUrl?.default || ""} />
```

### Boolean Types

Boolean properties can be `true | false | null`, not just `true | false | undefined`.

**❌ Wrong:**
```typescript
<video autoPlay={opti.autoplay} />
// Error: Type 'boolean | null' is not assignable to type 'boolean | undefined'
```

**✅ Correct:**
```typescript
<video autoPlay={opti.autoplay === true} />
```

### JSON Property Arrays

When using `type: "json"` for arrays, you must cast the type in your component:

**1. Define the TypeScript type:**
```typescript
type ContactInfo = {
  type: string;
  label: string;
  value: string;
};
```

**2. Add property to content type:**
```typescript
contactInfo: {
  type: "json",
  displayName: "Contact Information",
  description: "Array of contact information items",
}
```

**3. Use with type guards and casting:**
```typescript
{opti.contactInfo && Array.isArray(opti.contactInfo) && opti.contactInfo.length > 0 && (
  <div>
    {(opti.contactInfo as ContactInfo[]).map((info, i) => (
      <div key={i}>
        <span>{info.label}</span>
        <span>{info.value}</span>
      </div>
    ))}
  </div>
)}
```

### Content Array Items

When mapping over content arrays, the items may need explicit type casting:

```typescript
{opti.items.map((item, index) => {
  // Cast to the expected type
  const accordionItem = item as unknown as Infer<typeof AccordionItemType>;

  return (
    <div key={index}>
      {accordionItem.question}
      {accordionItem.answer}
    </div>
  );
})}
```

## Component Patterns

### Container + Item Pattern

Some components require both a container and item content type (e.g., AccordionBlock + AccordionItem).

**1. Create the item component:**
```typescript
// AccordionItem.tsx
export const AccordionItemType = contentType({
  key: "AccordionItem",
  baseType: "_component",
  properties: {
    question: { type: "string", displayName: "Question" },
    answer: { type: "string", displayName: "Answer" },
  },
});

// Data-only component (not rendered directly)
export default function AccordionItem({ opti }: Props) {
  return null;
}
```

**2. Reference it in the container:**
```typescript
// AccordionBlock.tsx
import { AccordionItemType } from "./AccordionItem";

export const AccordionBlockType = contentType({
  key: "AccordionBlock",
  baseType: "_component",
  properties: {
    items: {
      type: "array",
      items: {
        type: "content",
        allowedTypes: [AccordionItemType],
      },
    },
  },
});
```

**3. Register BOTH in layout.tsx:**
```typescript
import AccordionBlock, { AccordionBlockType } from "@/components/AccordionBlock";
import AccordionItem, { AccordionItemType } from "@/components/AccordionItem";

initContentTypeRegistry([
  AccordionBlockType,
  AccordionItemType,  // Don't forget this!
]);

initReactComponentRegistry({
  resolver: {
    AccordionBlock,
    AccordionItem,  // And this!
  },
});
```

## Common Type Patterns Quick Reference

| Scenario | Solution |
|----------|----------|
| URL for Link href | `opti.url?.default \|\| "#"` |
| URL for iframe src | `opti.embedUrl?.default \|\| ""` |
| Boolean for HTML attrs | `opti.autoplay === true` |
| JSON array | `Array.isArray(opti.items) && (opti.items as MyType[]).map(...)` |
| Content array items | `item as unknown as Infer<typeof ItemType>` |
| Numeric types | Use `"integer"` or `"float"`, NOT `"number"` |
| Default values | Handle in component, NOT in schema |
| Null checks | `opti.value !== null && opti.value !== undefined` |

## Property Type Cheat Sheet

| What You Need | Type to Use | Example |
|---------------|-------------|---------|
| Number field | `"integer"` or `"float"` | Rating, price, quantity |
| Simple URL | `"url"` | External link |
| Rich link | `"link"` | Link with text + target |
| Simple data array | `"json"` | Contact info, stats |
| Content array | `"array"` with `items: { type: "content" }` | Related articles |
| Single content | `"content"` | Featured image |
| Typed component | `"component"` with `contentType: MyType` | SEO block |

## When to Use Each Content Property Type

### `type: "content"` vs `type: "contentReference"`

Both reference other content, but with different purposes:

**Use `"contentReference"`** for media and assets:
```typescript
featuredImage: {
  type: "contentReference",
  displayName: "Featured Image",
  allowedTypes: ["_image"],
}
```

**Use `"content"`** for components and content blocks:
```typescript
hero: {
  type: "content",
  displayName: "Hero Section",
  allowedTypes: [HeroBlockType],
}
```

### `type: "component"` for Strong Typing

Use `"component"` when you want strong typing and always reference a specific type:

```typescript
import { SeoBlockType } from "./SeoBlock";

seo: {
  type: "component",
  contentType: SeoBlockType,  // Strongly typed
  displayName: "SEO Settings",
}
```

## Visual Builder Preview Errors

### "Content type 'BlankExperience' not included in the registry"

**Error**: When loading preview in Visual Builder, you get: `Content type "BlankExperience" not included in the registry. Ensure that you called "initContentTypeRegistry()" with it before fetching content.`

**Cause**: The SDK's built-in experience types (`BlankExperienceContentType`, `BlankSectionContentType`) are not registered.

**Solution**: Create an SDK initialization file and import it in your root layout:

**1. Create `src/optimizely.ts`:**
```typescript
import {
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

// Import your content types
import * as contentTypes from '@/src/cms/content-types';

// Import your React components
import BlankExperience from '@/components/cms/experiences/BlankExperience';
import BlankSection from '@/components/cms/experiences/BlankSection';
import { HeroBlock } from '@/components/cms/blocks/HeroBlock';
// ... other component imports

// Initialize content type registry - MUST include BlankExperience and BlankSection
initContentTypeRegistry([
  BlankExperienceContentType,  // Required for Visual Builder!
  BlankSectionContentType,     // Required for Visual Builder!
  ...Object.values(contentTypes),
]);

// Initialize display templates
initDisplayTemplateRegistry([/* your display templates */]);

// Initialize React component registry
initReactComponentRegistry({
  resolver: {
    BlankExperience,  // Required for Visual Builder!
    BlankSection,     // Required for Visual Builder!
    HeroBlock,
    // ... other components
  },
});
```

**2. Create experience components:**

**`components/cms/experiences/BlankExperience.tsx`:**
```typescript
import { BlankExperienceContentType, Infer } from '@optimizely/cms-sdk';
import {
  ComponentContainerProps,
  OptimizelyExperience,
  getPreviewUtils,
} from '@optimizely/cms-sdk/react/server';

type Props = {
  opti: Infer<typeof BlankExperienceContentType>;
};

function ComponentWrapper({ children, node }: ComponentContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="mb-8" {...pa(node)}>{children}</div>;
}

export default function BlankExperience({ opti }: Props) {
  return (
    <main className="blank-experience">
      <OptimizelyExperience
        nodes={opti.composition.nodes ?? []}
        ComponentWrapper={ComponentWrapper}
      />
    </main>
  );
}
```

**`components/cms/experiences/BlankSection.tsx`:**
```typescript
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
  const { pa } = getPreviewUtils(opti);
  return (
    <section className="vb:grid relative w-full py-12 px-4" {...pa(opti)}>
      <div className="max-w-7xl mx-auto w-full">
        <OptimizelyGridSection nodes={opti.nodes} row={Row} column={Column} />
      </div>
    </section>
  );
}

function Row({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="vb:row flex flex-row gap-6" {...pa(node)}>{children}</div>;
}

function Column({ children, node }: StructureContainerProps) {
  const { pa } = getPreviewUtils(node);
  return <div className="vb:col flex-1 flex flex-col gap-4" {...pa(node)}>{children}</div>;
}
```

**3. Import in root layout (`app/layout.tsx`):**
```typescript
import '@/src/optimizely';  // Initialize before any CMS content renders
```

---

### Preview Returns 404

**Error**: Visual Builder preview URL returns 404: `GET /preview?key=...&ver=...&loc=...&ctx=edit&preview_token=... 404`

**Cause**: Missing `/app/preview/page.tsx` route.

**Solution**: Create a preview page that uses the SDK's preview components:

**`app/preview/page.tsx`:**
```typescript
import { GraphClient, type PreviewParams } from '@optimizely/cms-sdk';
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
import Script from 'next/script';

type Props = {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>;
};

export default async function PreviewPage({ searchParams }: Props) {
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
  });

  const response = await client.getPreviewContent(
    (await searchParams) as PreviewParams
  );

  return (
    <div>
      {/* Communication injector - REQUIRED for Visual Builder */}
      <Script
        src={`${process.env.OPTIMIZELY_CMS_URL}/util/javascript/communicationinjector.js`}
        strategy="afterInteractive"
      />
      <PreviewComponent />
      <OptimizelyComponent opti={response} />
    </div>
  );
}
```

**Key components:**
- `OptimizelyComponent` - renders content using registered components
- `PreviewComponent` - enables Visual Builder client-side features
- Communication injector script - enables Visual Builder ↔ preview communication

---

### Preview Shows Blank or Doesn't Update

**Cause**: Missing communication injector script or incorrect environment variables.

**Check:**
1. Ensure `OPTIMIZELY_CMS_URL` is set (e.g., `https://app-xxx.cms.optimizely.com`)
2. Ensure `OPTIMIZELY_GRAPH_GATEWAY` includes the full path: `https://cg.optimizely.com/content/v2`
3. Verify the communication injector script is loaded in the preview page

---

### Preview Window Scrolls Indefinitely (Tailwind)

**Cause**: Using viewport-based height classes like `min-h-screen` or `min-h-[90vh]` in components. The Visual Builder preview renders in an iframe with its own viewport, causing these classes to create unexpected infinite scrolling behavior.

**❌ Avoid in CMS components:**
```typescript
// These cause issues in Visual Builder preview
<div className="min-h-screen ...">
<div className="min-h-[90vh] ...">
<div className="h-screen ...">
```

**✅ Use instead:**
```typescript
// Let content determine height with padding
<div className="py-20 ...">

// Or use fixed minimum heights
<div className="min-h-[400px] ...">
<div className="min-h-96 ...">
```

**Rule**: Avoid viewport-relative units (`vh`, `vw`, `dvh`, `svh`) in CMS components that will be previewed in Visual Builder. Use fixed values or let content/padding determine sizing.

---

### Content Not Found (getContentByPath returns 0 items)

**Cause**: The path format doesn't match how Optimizely Content Graph expects it.

**Key requirements for `getContentByPath`:**

1. **Trailing slash is required**: `/en/` not `/en`
2. **Include locale in path**: Don't strip the locale segment
3. **No variation filter needed**: Basic content fetching works without locale filtering

**❌ Wrong:**
```typescript
// Missing trailing slash
const content = await client.getContentByPath('/en');

// Stripping locale and querying root
const content = await client.getContentByPath('/');
```

**✅ Correct:**
```typescript
// Full path with trailing slash
const content = await client.getContentByPath(`/${slug.join('/')}/`);

// Examples:
// URL /en → path "/en/"
// URL /en/about → path "/en/about/"
```

---

## After Making Changes

After adding or modifying content types:

1. **Restart dev server** if types aren't recognized
2. **Run `npm run cms:push-config`** to sync with CMS
3. **Check `definitions.json`** (auto-generated, don't edit)
4. **Use `cms:push-config-force`** if there are conflicts

## InferredContentReference vs InferredUrl

The SDK has different inferred types for different scenarios:

```typescript
// For contentReference properties (images, media)
featuredImage: InferredContentReference | null

// For url properties
websiteUrl: InferredUrl | null

// Access the actual URL from InferredUrl
const url = opti.websiteUrl?.default || "";

// Access image URL from contentReference
const imageUrl = opti.featuredImage?.url;
```
