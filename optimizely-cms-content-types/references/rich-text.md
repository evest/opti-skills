# RichText Component Reference (v2)

`RichText` renders Optimizely CMS rich-text content (Slate.js JSON) as React elements. Safer than `dangerouslySetInnerHTML` and fully customisable via the `elements` and `leafs` props.

## Import

```typescript
import { RichText } from '@optimizely/cms-sdk/react/richText';
```

> Note the path: `@optimizely/cms-sdk/react/richText` (camelCase), not `/react/richtext`.

## Basic Usage

```tsx
import { RichText } from '@optimizely/cms-sdk/react/richText';

export default function Article({ content }) {
  return (
    <article>
      <RichText content={content.body?.json} />
    </article>
  );
}
```

`content.body?.json` is the standard shape — a property defined as `type: 'richText'` resolves to an object with a `.json` field carrying the Slate.js tree.

## Props

| Prop | Type | Description |
|------|------|-------------|
| `content` | `{ type: 'richText', children: Node[] } \| null \| undefined` | The rich-text JSON tree |
| `elements?` | `Record<string, React.ComponentType<ElementProps>>` | Override block/inline element rendering |
| `leafs?` | `Record<string, React.ComponentType<LeafProps>>` | Override text-formatting mark rendering |
| `decodeHtmlEntities?` | `boolean` (default `true`) | Decode `&lt;` → `<`, `&amp;` → `&`, etc. |

`RichText` does NOT accept `className`. Wrap it in a styled element instead:

```tsx
// ❌ Wrong — className is not a prop
<RichText content={content.body?.json} className="prose" />

// ✅ Correct
<div className="prose prose-lg">
  <RichText content={content.body?.json} />
</div>
```

## Default Element Mappings

These element types render to standard HTML by default. Override any via the `elements` prop.

- **Headings:** `heading-one` → `<h1>`, `heading-two` → `<h2>`, … `heading-six` → `<h6>`
- **Text blocks:** `paragraph`, `quote`, `div`
- **Lists:** `bulleted-list`, `numbered-list`, `list-item`
- **Inline text:** `span`, `mark`, `strong`, `em`, `u`, `s`, `i`, `b`, `small`, `sub`, `sup`, `ins`, `del`, `kbd`, `abbr`, `cite`, `dfn`, `q`, `data`, `bdo`, `bdi`
- **Code:** `code`, `pre`, `var`, `samp`
- **Interactive:** `link`, `a`, `button`, `label`
- **Tables:** `table`, `thead`, `tbody`, `tfoot`, `caption`, `tr`, `th`, `td`

**SVG elements are NOT supported** by default. Use custom element handlers, upload SVG as image assets, or build dedicated React components.

## Default Leaf (Mark) Mappings

- `bold` → `<strong>`
- `italic` → `<em>`
- `underline` → `<u>`
- `strikethrough` → `<s>`
- `code` → `<code>`

## Unknown Element Fallback

Unknown elements and unknown text marks render as `<span>`. This keeps HTML valid in any context (inline or block), avoids React hydration errors, and lets you style them via CSS if needed. Custom CMS elements introduced via the Integration API will use this fallback unless you provide handlers.

## Custom Elements

Provide React components keyed by element type. Each receives `{ children, element }` (typed as `ElementProps`).

```tsx
import { RichText, ElementProps } from '@optimizely/cms-sdk/react/richText';

const CustomHeading = ({ children }: ElementProps) => (
  <h1 className="text-4xl font-bold text-blue-600 mb-4">{children}</h1>
);

const CustomLink = ({ children, element }: ElementProps) => {
  const link = element as { url: string; target?: string; rel?: string };
  return (
    <a
      href={link.url}
      target={link.target}
      rel={link.rel}
      className="text-blue-500 hover:underline"
    >
      {children}
    </a>
  );
};

const CustomQuote = ({ children }: ElementProps) => (
  <blockquote className="border-l-4 border-gray-300 pl-4 italic">
    {children}
  </blockquote>
);

export default function Article({ content }) {
  return (
    <RichText
      content={content.body?.json}
      elements={{
        'heading-one': CustomHeading,
        link: CustomLink,
        quote: CustomQuote,
      }}
    />
  );
}
```

## Custom Leafs

Override how text-formatting marks render. Each receives `{ children, leaf }` (typed as `LeafProps`).

```tsx
import { RichText, LeafProps } from '@optimizely/cms-sdk/react/richText';

const CustomBold = ({ children }: LeafProps) => (
  <strong className="font-extrabold text-gray-900">{children}</strong>
);

const CustomCode = ({ children }: LeafProps) => (
  <code className="bg-gray-100 px-1 py-0.5 rounded font-mono text-sm text-red-600">
    {children}
  </code>
);

const CustomHighlight = ({ children }: LeafProps) => (
  <mark className="bg-yellow-200 px-1 rounded">{children}</mark>
);

export default function Article({ content }) {
  return (
    <RichText
      content={content.body?.json}
      leafs={{
        bold: CustomBold,
        code: CustomCode,
        highlight: CustomHighlight,  // custom mark from CMS
      }}
    />
  );
}
```

## `decodeHtmlEntities`

Controls whether HTML entities in text content are decoded before rendering.

```tsx
// Default — entities are decoded
<RichText content={content.body?.json} />
// '&lt;div&gt;' is rendered as '<div>'

// Preserve entities as-is — useful for code examples
<RichText content={content.body?.json} decodeHtmlEntities={false} />
// '&lt;div&gt;' stays as '&lt;div&gt;'
```

## TypeScript Types

```tsx
import {
  RichText,
  RichTextProps,
  ElementProps,
  LeafProps,
  ElementMap,
  LeafMap,
} from '@optimizely/cms-sdk/react/richText';

const elements: ElementMap = {
  'heading-one': CustomHeading,
  paragraph: CustomParagraph,
};

const leafs: LeafMap = {
  bold: CustomBold,
  italic: CustomItalic,
};
```

## Preview Token Handling

When the page is rendered inside a `withAppContext`-wrapped preview route, `RichText` automatically appends the active `preview_token` to image URLs inside the rich-text tree. No manual work needed for image preview tokens.

## HTML Attribute & CSS Property Handling

`RichText` converts CMS-authored HTML attributes to React-compatible props (`class` → `className`, `for` → `htmlFor`, `colspan` → `colSpan`, etc.) and moves CSS properties (`background-color`, `font-size`, …) into the `style` object with camelCase keys.

**Attributes that work as-is:** `id`, `name`, `value`, `type`, `href`, `src`, `alt`, `title`, `disabled`, `checked`, `required`, `placeholder`, `pattern`, `min`, `max`, `step`, `width`, `height`, `aria-*`, `data-*`, and most standard HTML attributes.

**Dual-purpose attributes** like `width`/`height`/`border` are treated as HTML attributes on tables and images, CSS properties elsewhere.

**Limitations** (custom handling needed):
- CSS custom properties (`--my-var`)
- Multi-column layout (`columns`, `column-count`)
- CSS masking and ruby properties
- Logical properties (`margin-inline-start`, etc.)
- Print-only properties (`page-break-*`, `orphans`, `widows`)

For unsupported properties, provide a custom element component and pull the raw values out of `element` / `attributes` yourself.

## Integration API caveats

When rich-text content is created via Optimizely's Integration API (REST) rather than the TinyMCE editor, some features may not behave as expected:
- Inline styles may use unsupported CSS properties
- HTML validation is bypassed (malformed HTML possible)
- Advanced TinyMCE-derived formatting may be missing
- Custom attributes may not map correctly to React props
- Security sanitization performed by the editor doesn't run

For full feature support, create rich-text content via the CMS editor where possible.

## Complete Example

```tsx
import {
  RichText,
  ElementProps,
  LeafProps,
} from '@optimizely/cms-sdk/react/richText';

const Heading = ({ children }: ElementProps) => (
  <h1 className="text-3xl font-bold mb-4 text-slate-800">{children}</h1>
);

const Paragraph = ({ children }: ElementProps) => (
  <p className="mb-4 text-slate-600 leading-relaxed">{children}</p>
);

const Link = ({ children, element }: ElementProps) => {
  const link = element as { url: string; target?: string };
  return (
    <a
      href={link.url}
      target={link.target}
      className="text-blue-600 hover:text-blue-800 underline"
    >
      {children}
    </a>
  );
};

const Bold = ({ children }: LeafProps) => (
  <strong className="font-semibold text-slate-900">{children}</strong>
);

const Code = ({ children }: LeafProps) => (
  <code className="bg-slate-100 px-2 py-1 rounded text-sm font-mono">
    {children}
  </code>
);

export default function Article({ content }) {
  return (
    <article className="prose max-w-none">
      <RichText
        content={content.body?.json}
        elements={{
          'heading-one': Heading,
          paragraph: Paragraph,
          link: Link,
        }}
        leafs={{
          bold: Bold,
          code: Code,
        }}
      />
    </article>
  );
}
```
