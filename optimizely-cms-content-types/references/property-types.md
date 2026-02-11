# Property Types Reference

Complete reference for all property types in Optimizely SaaS CMS Content JS SDK, based on the official SDK documentation.

## Base Property Options

All property types support these common options:

```typescript
{
  displayName?: string;      // Friendly name shown in CMS
  description?: string;      // Tooltip help text
  required?: boolean;        // Must have a value
  localized?: boolean;       // Different value per locale/language
  group?: string;            // Property group key
  sortOrder?: number;        // Display order (lower numbers first)
  indexingType?: 'searchable' | 'queryable' | 'disabled';  // Default: 'searchable'
  format?: string;           // Predefined format reference
}
```

## String Property

Simple text fields for titles, names, short descriptions.

```typescript
title: {
  type: 'string',
  displayName: 'Title',
  description: 'Help text for editors',
  required: false,
  localized: false,
  minLength: 0,
  maxLength: 255,
  pattern: '',  // Regular expression
  enum: [       // Predefined values
    { value: 'option1', displayName: 'Option 1' },
    { value: 'option2', displayName: 'Option 2' },
  ],
}
```

**Unique options:**
- `minLength?: number`
- `maxLength?: number`
- `pattern?: string` - Regex pattern
- `enum?: { value: string; displayName: string }[]`

> **Important:** Only use `enum` for semantic/content choices (heading levels, categories, status values). For visual styling options (colors, sizes, button variants, alignment), use `displayTemplate` instead. See `references/standard-types.md` for display template examples.

## Rich Text Property

Formatted content with rich text editing capabilities (Slate.js format).

```typescript
body: {
  type: 'richText',
  displayName: 'Article Body',
  description: 'Full rich text editing',
  required: false,
  localized: true,
}
```

**Use for:** Article bodies, descriptions, formatted content, long text

## URL Property

**For simple web addresses as strings.**

```typescript
websiteUrl: {
  type: 'url',
  displayName: 'Website URL',
  description: 'External website link',
  required: false,
}
```

**Use for:** Simple URL storage, external links, website addresses

## Link Property

**For rich link objects with all `<a>` tag attributes (text, title, target).**

```typescript
ctaLink: {
  type: 'link',
  displayName: 'Call to Action Link',
  description: 'Link with title and target options',
  required: false,
}
```

**Use for:** Navigation links, CTAs, links that need text/title/target metadata

**KEY DIFFERENCE:** Use `url` for simple URL storage, use `link` when you need text, title, and target attributes along with the URL.

## Boolean Property

True/false checkbox.

```typescript
isPublished: {
  type: 'boolean',
  displayName: 'Published',
  description: 'Make this content publicly visible',
}
```

**Use for:** Flags, toggles, enable/disable options

## Integer Property

Whole numbers.

```typescript
quantity: {
  type: 'integer',
  displayName: 'Quantity',
  minimum: 1,
  maximum: 100,
  enum: [
    { value: 5, displayName: '5 items' },
    { value: 10, displayName: '10 items' },
  ],
}
```

**Unique options:**
- `minimum?: number`
- `maximum?: number`
- `enum?: { value: number; displayName: string }[]`

**Use for:** Counts, limits, rankings, order values, quantities

## Float Property

Decimal numbers.

```typescript
price: {
  type: 'float',
  displayName: 'Price',
  minimum: 0.01,
  maximum: 99999.99,
}
```

**Unique options:**
- `minimum?: number`
- `maximum?: number`
- `enum?: { value: number; displayName: string }[]`

**Use for:** Prices, ratings, percentages, measurements

## DateTime Property

Date and time values with optional constraints.

```typescript
publishDate: {
  type: 'dateTime',
  displayName: 'Publish Date',
  required: true,
}

eventStartTime: {
  type: 'dateTime',
  displayName: 'Event Start',
  minimum: '2025-12-01T00:00:00Z',  // ISO 8601 format
  maximum: '2025-12-31T23:59:59Z',
}
```

**Unique options:**
- `minimum?: string` - Earliest allowed (ISO 8601)
- `maximum?: string` - Latest allowed (ISO 8601)

**Use for:** Publish dates, event dates, timestamps, schedules

## Array Property

Lists of values. **IMPORTANT: Cannot contain nested arrays.**

**⚠️ IMPORTANT RESTRICTION**: Content types with `elementEnabled` **CANNOT** have array properties that contain content items (`type: "array"` with `items: { type: "content" }`). Elements are meant to be simple, atomic components, not containers.

If your component needs to contain arrays of other content (like AccordionBlock with AccordionItems), use **only** `compositionBehaviors: ['sectionEnabled']`.

### String Array

```typescript
tags: {
  type: 'array',
  displayName: 'Tags',
  items: { 
    type: 'string',
    maxLength: 50,
  },
  minItems: 1,
  maxItems: 10,
}
```

### Content Array

```typescript
relatedArticles: {
  type: 'array',
  displayName: 'Related Articles',
  items: {
    type: 'content',
    allowedTypes: ['ArticlePage'],
  },
  maxItems: 5,
}
```

### ContentReference Array

```typescript
featuredImages: {
  type: 'array',
  displayName: 'Image Gallery',
  items: {
    type: 'contentReference',
    allowedTypes: ['_image'],
  },
}
```

**Unique options:**
- `items: PropertyType` - Required: type of array items
- `minItems?: number`
- `maxItems?: number`

**Supported item types:** string, boolean, binary, json, dateTime, richText, url, integer, float, contentReference, content, component, link

**NOT supported:** Array items cannot be arrays (no nested arrays)

## ContentReference Property

Reference to another content item (page, block, media).

```typescript
featuredImage: {
  type: 'contentReference',
  displayName: 'Featured Image',
  allowedTypes: ['_image'],
  restrictedTypes: [],
}
```

**Unique options:**
- `allowedTypes?: Array<ContentType | string>`
- `restrictedTypes?: Array<ContentType | string>`

**Use for:** Images, linked pages, related content, media files

## Content Property

Reference to another content item (page, block, media), **or** or an inline block. This property allows the creation of a block for inline storage in the property. You can point to a shared block and then select to convert it to an inline block copying the content onto the page breaking the link to the original.

```typescript
heroSection: {
  type: 'content',
  displayName: 'Hero Section',
  allowedTypes: ['HeroBlock'],
  restrictedTypes: ['_folder'],
}
```

**Unique options:**
- `allowedTypes?: Array<ContentType | string>`
- `restrictedTypes?: Array<ContentType | string>`

**Use for:** Nested blocks, composed content, content areas

**Difference from contentReference:** Content may be embedded inline vs. referenced by ID, but it can still be a reference to another content item.

**Important restriction: It is not allowed to have an inline property of type content on an element **

**⚠️ IMPORTANT RESTRICTION**: Content types with `elementEnabled` **CANNOT** have properties that are content items (`type: "content"`). Elements are meant to be simple, atomic components, not containers.

Use `ContentReference` instead to reference a shared block or page.

## Component Property

Specific component/block type (strongly typed).

```typescript
import { HeroBlockCT } from './HeroBlock';

hero: {
  type: 'component',
  contentType: HeroBlockCT,  // Required
  displayName: 'Hero Section',
}
```

**Unique options:**
- `contentType: ContentType` - Required: specific content type

**Use for:** When you need a specific block type, type-safe embedding


## Binary Property

Binary data storage for file uploads.

```typescript
attachment: {
  type: 'binary',
  displayName: 'Attachment',
  description: 'Upload a file',
}
```

**Use for:** File uploads, attachments, binary assets

## JSON Property

JSON data storage for structured data.

```typescript
metadata: {
  type: 'json',
  displayName: 'Metadata',
  description: 'Additional metadata in JSON format',
}
```

**Use for:** Structured metadata, configuration data, flexible data storage

**⚠️ IMPORTANT RESTRICTION**: Content types with `elementEnabled` **CANNOT** have properties that are of  type `json`. Elements are meant to be simple, atomic components, not containers.


## Indexing Types

Controls how properties are indexed for search. **Default is 'searchable'.**

```typescript
{
  type: 'string',
  displayName: 'Search Term',
  indexingType: 'searchable',  // Default value
}
```

**Options:**
- **`'searchable'`** (default) - Fully indexed for full-text search
- **`'queryable'`** - Can be filtered/sorted but not full-text searched
- **`'disabled'`** - Not indexed at all

**Example:**

```typescript
properties: {
  title: {
    type: 'string',
    indexingType: 'searchable',   // Full-text search
  },
  publishDate: {
    type: 'dateTime',
    indexingType: 'queryable',    // Filter/sort only
  },
  internalNotes: {
    type: 'string',
    indexingType: 'disabled',     // Not searchable
  },
}
```

## AllowedTypes & RestrictedTypes

For `content`, `contentReference`, and array items with these types:

```typescript
featuredArticle: {
  type: 'content',
  allowedTypes: [ArticleCT],  // Whitelist
}

relatedContent: {
  type: 'content',
  restrictedTypes: ['_folder'],  // Blacklist
}
```

**AllowedTypes options:**
- Specific content types: `[ArticleCT, VideoCT]`
- Base types: `['_page', '_component', '_image']`
- Self-reference: `['_self']`

**RestrictedTypes:** Same format as allowedTypes

## Validation Examples

### String with Constraints

```typescript
{
  type: 'string',
  minLength: 5,
  maxLength: 100,
  pattern: '^[A-Za-z0-9 ]+$',
}
```

### Number Range

```typescript
{
  type: 'integer',
  minimum: 1,
  maximum: 100,
}
```

### Array Limits

```typescript
{
  type: 'array',
  items: { type: 'string' },
  minItems: 1,
  maxItems: 10,
}
```

### Enum with Display Names

Use enum for **semantic/content choices**, not visual styling:

```typescript
// ✅ Correct: semantic choice (heading level affects document structure)
{
  type: 'string',
  displayName: 'Heading Level',
  enum: [
    { value: 'h1', displayName: 'H1' },
    { value: 'h2', displayName: 'H2' },
    { value: 'h3', displayName: 'H3' },
  ],
}

// ✅ Correct: content category
{
  type: 'string',
  displayName: 'Article Category',
  enum: [
    { value: 'news', displayName: 'News' },
    { value: 'tutorial', displayName: 'Tutorial' },
    { value: 'review', displayName: 'Review' },
  ],
}
```

> **For visual styling** (sizes, colors, button variants, alignment), use `displayTemplate` instead. See `references/standard-types.md#display-templates`.

## Complete Example

```typescript
export const ArticlePageCT = contentType({
  key: 'ArticlePage',
  baseType: '_page',
  properties: {
    // String with validation
    title: {
      type: 'string',
      displayName: 'Article Title',
      description: 'The main title',
      required: true,
      localized: true,
      group: 'content',
      sortOrder: 10,
      minLength: 10,
      maxLength: 200,
      indexingType: 'searchable',
    },
    // Rich text
    body: {
      type: 'richText',
      displayName: 'Article Body',
      required: true,
      localized: true,
      group: 'content',
      sortOrder: 20,
    },
    // URL property (simple)
    externalUrl: {
      type: 'url',
      displayName: 'External URL',
      group: 'links',
      sortOrder: 30,
    },
    // Link property (rich)
    ctaLink: {
      type: 'link',
      displayName: 'CTA Link',
      description: 'Link with text and target',
      group: 'links',
      sortOrder: 40,
    },
    // Content reference
    featuredImage: {
      type: 'contentReference',
      displayName: 'Featured Image',
      group: 'media',
      sortOrder: 50,
      allowedTypes: ['_image'],
    },
    // Array
    tags: {
      type: 'array',
      displayName: 'Tags',
      group: 'meta',
      sortOrder: 60,
      items: {
        type: 'string',
        maxLength: 30,
      },
      maxItems: 10,
    },
    // Boolean
    featured: {
      type: 'boolean',
      displayName: 'Featured Article',
      group: 'meta',
      sortOrder: 70,
    },
    // DateTime
    publishDate: {
      type: 'dateTime',
      displayName: 'Publish Date',
      required: true,
      group: 'scheduling',
      sortOrder: 80,
      indexingType: 'queryable',
    },
  },
});
```

## Summary of Property Types

| Type | Description | Example Use |
|------|-------------|-------------|
| `string` | Simple text | Titles, names, labels |
| `richText` | Formatted content | Article bodies, descriptions |
| `url` | Simple web address | Website links, external URLs |
| `link` | Rich link with metadata | CTAs, navigation links |
| `boolean` | True/false | Flags, toggles |
| `integer` | Whole number | Counts, limits, rankings |
| `float` | Decimal number | Prices, ratings |
| `dateTime` | Date and time | Publish dates, events |
| `array` | List of items | Tags, galleries, lists |
| `contentReference` | Content reference | Images, linked pages |
| `content` | Embedded content | Nested blocks |
| `component` | Specific component | Strongly-typed blocks |
| `binary` | Binary data | File uploads |
| `json` | JSON data | Metadata, config |
