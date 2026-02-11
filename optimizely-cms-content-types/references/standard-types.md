# Standard Content Types

Ready-to-use content type definitions following official SDK conventions.

## Page Types

### HomePage

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const HomePageCT = contentType({
  key: 'HomePage',
  displayName: 'Home Page',
  baseType: '_page',
  properties: {
    heading: { 
      type: 'string', 
      displayName: 'Page Heading',
      required: true,
      localized: true,
      indexingType: 'searchable',
    },
    subheading: { 
      type: 'string', 
      displayName: 'Subheading',
      localized: true,
    },
    heroImage: { 
      type: 'contentReference', 
      displayName: 'Hero Image',
      allowedTypes: ['_image'],
    },
    mainContent: { 
      type: 'richText', 
      displayName: 'Main Content',
      localized: true,
    },
    featuredSections: {
      type: 'array',
      displayName: 'Featured Sections',
      items: { type: 'content' },
      maxItems: 3,
    },
  },
});
```

### ArticlePage

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const ArticlePageCT = contentType({
  key: 'ArticlePage',
  displayName: 'Article Page',
  baseType: '_page',
  properties: {
    heading: { 
      type: 'string', 
      displayName: 'Article Title',
      required: true,
      localized: true,
      maxLength: 200,
      indexingType: 'searchable',
    },
    author: { 
      type: 'string', 
      displayName: 'Author',
    },
    publishDate: { 
      type: 'dateTime', 
      displayName: 'Publish Date',
      required: true,
      indexingType: 'queryable',
    },
    featuredImage: { 
      type: 'contentReference', 
      displayName: 'Featured Image',
      allowedTypes: ['_image'],
    },
    summary: { 
      type: 'string', 
      displayName: 'Article Summary',
      localized: true,
      maxLength: 500,
    },
    body: { 
      type: 'richText', 
      displayName: 'Article Content',
      required: true,
      localized: true,
    },
    tags: {
      type: 'array',
      displayName: 'Tags',
      items: { type: 'string', maxLength: 50 },
      maxItems: 10,
    },
    relatedArticles: {
      type: 'array',
      displayName: 'Related Articles',
      items: { 
        type: 'contentReference',
        allowedTypes: ['ArticlePage'],
      },
      maxItems: 5,
    },
  },
});
```

### BlogPage

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const BlogPageCT = contentType({
  key: 'BlogPage',
  displayName: 'Blog Page',
  baseType: '_page',
  properties: {
    title: { 
      type: 'string', 
      displayName: 'Blog Title',
      required: true,
      localized: true,
    },
    author: { 
      type: 'string', 
      displayName: 'Author',
      required: true,
    },
    publishDate: { 
      type: 'dateTime', 
      displayName: 'Publish Date',
      required: true,
    },
    category: { 
      type: 'string', 
      displayName: 'Category',
      enum: [
        { value: 'tech', displayName: 'Technology' },
        { value: 'business', displayName: 'Business' },
        { value: 'lifestyle', displayName: 'Lifestyle' },
        { value: 'news', displayName: 'News' },
      ],
    },
    featuredImage: { 
      type: 'contentReference', 
      displayName: 'Featured Image',
      allowedTypes: ['_image'],
    },
    excerpt: { 
      type: 'string', 
      displayName: 'Excerpt',
      localized: true,
      maxLength: 300,
    },
    content: { 
      type: 'richText', 
      displayName: 'Blog Content',
      required: true,
      localized: true,
    },
    allowComments: { 
      type: 'boolean', 
      displayName: 'Allow Comments',
    },
    tags: {
      type: 'array',
      displayName: 'Tags',
      items: { type: 'string' },
    },
  },
});
```

### LandingPage

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const LandingPageCT = contentType({
  key: 'LandingPage',
  displayName: 'Landing Page',
  baseType: '_page',
  properties: {
    heading: { 
      type: 'string', 
      displayName: 'Page Heading',
      required: true,
      localized: true,
    },
    subheading: { 
      type: 'string', 
      displayName: 'Subheading',
      localized: true,
    },
    heroSection: { 
      type: 'content', 
      displayName: 'Hero Section',
      allowedTypes: ['HeroBlock'],
    },
    contentSections: {
      type: 'array',
      displayName: 'Content Sections',
      items: { type: 'content' },
    },
    ctaText: { 
      type: 'string', 
      displayName: 'CTA Button Text',
    },
    ctaLink: { 
      type: 'link',  // Use link type for rich link with text/title/target
      displayName: 'CTA Button Link',
    },
    hideNavigation: { 
      type: 'boolean', 
      displayName: 'Hide Navigation',
    },
  },
});
```

## Component Types (Blocks)

### HeroBlock

> **Note:** Visual styling options like `imageAlignment` and `height` should be defined using `displayTemplate` instead of enum properties. See [Display Templates](#display-templates) section below.

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const HeroBlockCT = contentType({
  key: 'HeroBlock',
  displayName: 'Hero Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],  // Can be used as section
  properties: {
    title: {
      type: 'string',
      displayName: 'Title',
      required: true,
      localized: true,
    },
    subtitle: {
      type: 'string',
      displayName: 'Subtitle',
      localized: true,
    },
    backgroundImage: {
      type: 'contentReference',
      displayName: 'Background Image',
      allowedTypes: ['_image'],
    },
    ctas: {
      type: 'array',
      displayName: 'Call to Actions',
      items: { type: 'content' },
      maxItems: 3,
    },
  },
});
```

### CallToActionBlock

> **Note:** Visual styling options like `style` should be defined using `displayTemplate` instead of enum properties. See [Display Templates](#display-templates) section below.

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const CallToActionBlockCT = contentType({
  key: 'CallToActionBlock',
  displayName: 'Call To Action Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled', 'elementEnabled'],  // Works as both!
  properties: {
    heading: {
      type: 'string',
      displayName: 'Heading',
      required: true,
      localized: true,
    },
    description: {
      type: 'richText',
      displayName: 'Description',
      localized: true,
    },
    primaryButtonText: {
      type: 'string',
      displayName: 'Primary Button Text',
      required: true,
    },
    primaryButtonLink: {
      type: 'link',  // Rich link with text/title/target
      displayName: 'Primary Button Link',
      required: true,
    },
    secondaryButtonText: {
      type: 'string',
      displayName: 'Secondary Button Text',
    },
    secondaryButtonLink: {
      type: 'link',
      displayName: 'Secondary Button Link',
    },
  },
});
```

### CardBlock

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const CardBlockCT = contentType({
  key: 'CardBlock',
  displayName: 'Card Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled', 'elementEnabled'],  // Flexible usage
  properties: {
    heading: { 
      type: 'string', 
      displayName: 'Card Heading',
      required: true,
      localized: true,
    },
    image: { 
      type: 'contentReference', 
      displayName: 'Card Image',
      allowedTypes: ['_image'],
    },
    description: { 
      type: 'richText', 
      displayName: 'Card Description',
      localized: true,
    },
    linkText: { 
      type: 'string', 
      displayName: 'Link Text',
    },
    linkUrl: { 
      type: 'url',  // Simple URL
      displayName: 'Link URL',
    },
  },
});
```

## Element Types

> **Important:** Elements use `_component` as the base type with `compositionBehaviors: ['elementEnabled']`. There is no `_element` base type in Optimizely CMS.

### TitleElement

> **Note:** Visual styling options like `alignment` should be defined using `displayTemplate` instead of enum properties. The `level` property (h1-h6) is semantic content, so enum is appropriate there. See [Display Templates](#display-templates) section below.

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const TitleElementCT = contentType({
  key: 'TitleElement',
  displayName: 'Title Element',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    text: {
      type: 'string',
      displayName: 'Title Text',
      required: true,
      localized: true,
    },
    level: {
      type: 'string',
      displayName: 'Heading Level',
      enum: [
        { value: 'h1', displayName: 'H1' },
        { value: 'h2', displayName: 'H2' },
        { value: 'h3', displayName: 'H3' },
        { value: 'h4', displayName: 'H4' },
        { value: 'h5', displayName: 'H5' },
        { value: 'h6', displayName: 'H6' },
      ],
    },
  },
});
```

### ImageElement

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const ImageElementCT = contentType({
  key: 'ImageElement',
  displayName: 'Image Element',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    image: { 
      type: 'contentReference', 
      displayName: 'Image',
      required: true,
      allowedTypes: ['_image'],
    },
    altText: { 
      type: 'string', 
      displayName: 'Alt Text',
      required: true,
      localized: true,
    },
    caption: { 
      type: 'string', 
      displayName: 'Caption',
      localized: true,
    },
    link: { 
      type: 'url',  // Simple URL
      displayName: 'Image Link',
    },
  },
});
```

### ButtonElement

> **Note:** Visual styling options like `style` and `size` should be defined using `displayTemplate` instead of enum properties. See [Display Templates](#display-templates) section below.

```typescript
import { contentType, displayTemplate } from '@optimizely/cms-sdk';

// Content type - only content properties
export const ButtonElementCT = contentType({
  key: 'ButtonElement',
  displayName: 'Button Element',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    text: {
      type: 'string',
      displayName: 'Button Text',
      required: true,
      localized: true,
    },
    link: {
      type: 'link',  // Rich link with text/title/target
      displayName: 'Button Link',
      required: true,
    },
  },
});

// Display template - defines visual variations
export const ButtonDisplayTemplate = displayTemplate({
  key: 'ButtonDisplayTemplate',
  isDefault: true,
  displayName: 'Button Style',
  contentType: 'ButtonElement',
  settings: {
    style: {
      editor: 'select',
      displayName: 'Button Style',
      sortOrder: 0,
      choices: {
        primary: { displayName: 'Primary', sortOrder: 1 },
        secondary: { displayName: 'Secondary', sortOrder: 2 },
        outline: { displayName: 'Outline', sortOrder: 3 },
        text: { displayName: 'Text Only', sortOrder: 4 },
      },
    },
    size: {
      editor: 'select',
      displayName: 'Button Size',
      sortOrder: 1,
      choices: {
        sm: { displayName: 'Small', sortOrder: 1 },
        md: { displayName: 'Medium', sortOrder: 2 },
        lg: { displayName: 'Large', sortOrder: 3 },
      },
    },
  },
});
```

## Section Type

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const HeroSectionCT = contentType({
  key: 'HeroSection',
  displayName: 'Hero Section',
  baseType: '_section',
  properties: {
    backgroundImage: {
      type: 'contentReference',
      displayName: 'Background Image',
      allowedTypes: ['_image'],
    },
    backgroundColor: {
      type: 'string',
      displayName: 'Background Color',
      pattern: '^#[0-9A-Fa-f]{6}$',
    },
  },
});
```

## Experience Type

```typescript
import { contentType } from '@optimizely/cms-sdk';

export const AboutExperienceCT = contentType({
  key: 'AboutExperience',
  displayName: 'About Experience',
  baseType: '_experience',
  properties: {
    title: {
      type: 'string',
      displayName: 'Title',
      required: true,
    },
    subtitle: {
      type: 'string',
      displayName: 'Subtitle',
    },
  },
});
```

## Display Templates

Display templates define visual variations that editors can apply to components. **Use display templates for styling options instead of enum properties on content types.**

### When to Use Display Templates vs Enum Properties

| Use Display Template | Use Enum Property |
|---------------------|-------------------|
| Visual styling (colors, sizes, alignment) | Semantic content (heading level h1-h6) |
| Layout variations (orientation, spacing) | Content categories (blog category) |
| Component variants (primary/secondary button) | Data values (status, type) |
| Presentation options | Business logic choices |

**Key principle:** If changing the value affects how something *looks* (presentation), use `displayTemplate`. If it affects what something *means* (content/semantics), use `enum`.

### Basic Display Template

```typescript
import { contentType, displayTemplate, Infer } from '@optimizely/cms-sdk';

// Content type - only content properties
export const CardBlockCT = contentType({
  key: 'CardBlock',
  displayName: 'Card Block',
  baseType: '_component',
  compositionBehaviors: ['elementEnabled'],
  properties: {
    title: { type: 'string', displayName: 'Title', required: true },
    description: { type: 'string', displayName: 'Description' },
    image: { type: 'contentReference', displayName: 'Image', allowedTypes: ['_image'] },
  },
});

// Display template - defines visual variations
export const CardDisplayTemplate = displayTemplate({
  key: 'CardDisplayTemplate',
  isDefault: true,
  displayName: 'Card Style',
  contentType: 'CardBlock',  // Links to specific content type
  settings: {
    variant: {
      editor: 'select',
      displayName: 'Card Variant',
      sortOrder: 0,
      choices: {
        default: { displayName: 'Default', sortOrder: 1 },
        outlined: { displayName: 'Outlined', sortOrder: 2 },
        elevated: { displayName: 'Elevated', sortOrder: 3 },
      },
    },
    imagePosition: {
      editor: 'select',
      displayName: 'Image Position',
      sortOrder: 1,
      choices: {
        top: { displayName: 'Top', sortOrder: 1 },
        left: { displayName: 'Left', sortOrder: 2 },
        right: { displayName: 'Right', sortOrder: 3 },
      },
    },
  },
});
```

### Display Template with Component Variants (Tags)

Use `tag` to link a display template to a specific component variant:

```typescript
// Content type
export const HeroBlockCT = contentType({
  key: 'HeroBlock',
  displayName: 'Hero Block',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: {
    title: { type: 'string', displayName: 'Title', required: true },
    subtitle: { type: 'string', displayName: 'Subtitle' },
    backgroundImage: { type: 'contentReference', displayName: 'Background', allowedTypes: ['_image'] },
  },
});

// Default display template
export const HeroDefaultTemplate = displayTemplate({
  key: 'HeroDefaultTemplate',
  isDefault: true,
  displayName: 'Default Hero',
  contentType: 'HeroBlock',
  settings: {
    height: {
      editor: 'select',
      displayName: 'Height',
      sortOrder: 0,
      choices: {
        sm: { displayName: 'Small', sortOrder: 1 },
        md: { displayName: 'Medium', sortOrder: 2 },
        lg: { displayName: 'Large', sortOrder: 3 },
        full: { displayName: 'Full Screen', sortOrder: 4 },
      },
    },
  },
});

// Centered variant with different styling options
export const HeroCenteredTemplate = displayTemplate({
  key: 'HeroCenteredTemplate',
  isDefault: false,
  displayName: 'Centered Hero',
  contentType: 'HeroBlock',
  tag: 'Centered',  // Links to CenteredHero component variant
  settings: {
    textColor: {
      editor: 'select',
      displayName: 'Text Color',
      sortOrder: 0,
      choices: {
        light: { displayName: 'Light', sortOrder: 1 },
        dark: { displayName: 'Dark', sortOrder: 2 },
      },
    },
    overlay: {
      editor: 'checkbox',
      displayName: 'Show Overlay',
      sortOrder: 1,
      choices: {
        true: { displayName: 'Enabled', sortOrder: 1 },
        false: { displayName: 'Disabled', sortOrder: 2 },
      },
    },
  },
});
```

### Using Display Settings in Components

```typescript
import { Infer } from '@optimizely/cms-sdk';
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';

type Props = {
  opti: Infer<typeof CardBlockCT>;
  displaySettings?: Infer<typeof CardDisplayTemplate>;
};

export default function CardBlock({ opti, displaySettings }: Props) {
  const { pa } = getPreviewUtils(opti);

  return (
    <div
      className={`card card--${displaySettings?.variant ?? 'default'}`}
      data-image-position={displaySettings?.imagePosition ?? 'top'}
      {...pa(opti)}
    >
      {opti.image?.url?.default && (
        <img src={opti.image.url.default} alt="" {...pa('image')} />
      )}
      <h3 {...pa('title')}>{opti.title}</h3>
      <p {...pa('description')}>{opti.description}</p>
    </div>
  );
}
```

### Registering Display Templates

```typescript
// In your optimizely.ts setup file
import { initDisplayTemplateRegistry } from '@optimizely/cms-sdk';
import {
  CardDisplayTemplate,
  HeroDefaultTemplate,
  HeroCenteredTemplate,
  ButtonDisplayTemplate,
} from '@/components';

initDisplayTemplateRegistry([
  CardDisplayTemplate,
  HeroDefaultTemplate,
  HeroCenteredTemplate,
  ButtonDisplayTemplate,
]);
```

### Display Template Properties Reference

| Property | Required | Description |
|----------|----------|-------------|
| `key` | Yes | Unique identifier |
| `displayName` | Yes | Name shown to editors |
| `isDefault` | Yes | Whether this is the default template |
| `settings` | Yes | Object defining available styling options |
| `contentType` | One of these | Apply to specific content type |
| `baseType` | One of these | Apply to `'_component'`, `'_experience'`, or `'_section'` |
| `nodeType` | One of these | Apply to `'row'` or `'column'` |
| `tag` | No | Links to a component variant |
| `sortOrder` | No | Display order in CMS UI |

### Setting Editor Types

**Select** - Dropdown for single selection:
```typescript
color: {
  editor: 'select',
  displayName: 'Color',
  choices: {
    blue: { displayName: 'Blue', sortOrder: 1 },
    red: { displayName: 'Red', sortOrder: 2 },
  },
}
```

> **⚠️ IMPORTANT: Choice Key Naming Rules**
>
> Choice keys (the object property names in `choices`) must follow these rules:
> - Must start with a non-numerical character (letter or underscore)
> - Can only contain alphanumeric characters (a-z, A-Z, 0-9) or underscores
> - **NO hyphens allowed** - use underscores instead
>
> ```typescript
> // ❌ WRONG: Hyphens in choice keys
> choices: {
>   'light-grey': { displayName: 'Light Grey', sortOrder: 1 },
>   'dark-blue': { displayName: 'Dark Blue', sortOrder: 2 },
> }
>
> // ✅ CORRECT: Use underscores instead
> choices: {
>   light_grey: { displayName: 'Light Grey', sortOrder: 1 },
>   dark_blue: { displayName: 'Dark Blue', sortOrder: 2 },
> }
> ```
>
> If your component library expects hyphenated values (like Hedwig's `'lighter-brand'`), create a mapping in your React component to convert underscore keys to hyphenated values.

**Checkbox** - Toggle for boolean values:
```typescript
showBorder: {
  editor: 'checkbox',
  displayName: 'Show Border',
  choices: {
    true: { displayName: 'Enabled', sortOrder: 1 },
    false: { displayName: 'Disabled', sortOrder: 2 },
  },
}
```

## Usage Tips

1. **Copy entire definitions** - Ready to use
2. **Customize properties** - Add/remove as needed
3. **Update keys** - Ensure uniqueness
4. **Note URL vs Link** - Use `url` for simple URLs, `link` for rich links
5. **IndexingType** - Default is 'searchable'
6. **CompositionBehaviors** - Add for Visual Builder flexibility
7. **Property groups** - Add `group` field
8. **Export naming** - Use "CT" suffix
9. **Use displayTemplate for styling** - Don't put visual options in content type enums

## Component Pattern

```typescript
import { Infer } from '@optimizely/cms-sdk';
import { HeroBlockCT } from './HeroBlock';

type Props = {
  opti: Infer<typeof HeroBlockCT>;
};

export default function HeroBlock({ opti }: Props) {
  return (
    <div className="hero">
      <h1>{opti.title}</h1>
      <p>{opti.subtitle}</p>
    </div>
  );
}
```

## Rendering Images from Content References

**CRITICAL**: Image URLs from Optimizely content references use a nested structure and must be accessed via `.url.default`.

### Correct Image Rendering Pattern

```typescript
import { Infer } from '@optimizely/cms-sdk';
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';

type Props = {
  opti: Infer<typeof HeroBlockCT>;
};

export default function HeroBlock({ opti }: Props) {
  const { pa } = getPreviewUtils(opti);

  return (
    <div className="hero">
      {/* ✅ CORRECT: Access nested url.default property */}
      {opti.backgroundImage?.url?.default && (
        <img
          src={opti.backgroundImage.url.default}
          alt={opti.title || "Hero background"}
          className="hero-bg"
          {...pa("backgroundImage")}
        />
      )}

      {/* ✅ Also works with Next.js Image component */}
      {opti.backgroundImage?.url?.default && (
        <Image
          src={opti.backgroundImage.url.default}
          alt={opti.title || "Hero background"}
          fill
          className="hero-bg"
        />
      )}
    </div>
  );
}
```

### Common Mistakes to Avoid

```typescript
// ❌ WRONG: Using the reference object directly
<img src={opti.backgroundImage} alt="..." />
// Result: [object Object] or invalid URL error

// ❌ WRONG: Missing .url.default
<img src={opti.backgroundImage.url} alt="..." />
// Result: Still an object, not a string

// ✅ CORRECT: Full path to URL string
<img src={opti.backgroundImage?.url?.default} alt="..." />
```

### URL Structure Explanation

When you define a content reference to an image:

```typescript
backgroundImage: {
  type: 'contentReference',
  allowedTypes: ['_image'],
}
```

The runtime value structure is:

```typescript
{
  backgroundImage: {
    url: {
      default: "https://cdn.optimizely.com/...",
      // Other variants may exist
    },
    // Other metadata properties
  }
}
```

### Multiple Image References Example

```typescript
export default function TestimonialBlock({ opti }: Props) {
  const { pa } = getPreviewUtils(opti);

  return (
    <div>
      {/* Customer photo */}
      {opti.customerPhoto?.url?.default && (
        <img
          src={opti.customerPhoto.url.default}
          alt={opti.customerName || "Customer"}
          width={60}
          height={60}
          className="rounded-full"
          {...pa("customerPhoto")}
        />
      )}

      {/* Company logo */}
      {opti.companyLogo?.url?.default && (
        <img
          src={opti.companyLogo.url.default}
          alt="Company logo"
          className="logo"
          {...pa("companyLogo")}
        />
      )}
    </div>
  );
}
```

### Best Practices

1. **Always use optional chaining** (`?.`) when accessing image URLs to handle undefined references
2. **Check for url.default existence** before rendering image elements
3. **Use preview attributes** (`{...pa("propertyName")}`) for edit mode functionality
4. **Provide meaningful alt text** using content from your opti object when available
5. **Standard img vs Next.js Image**: Both work, but remember Next.js Image requires configuration in `next.config.ts` for external domains
