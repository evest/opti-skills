# DAM Asset Helpers Reference

The `damAssets` utility provides helper functions for working with Digital Asset Management (DAM) assets from Optimizely CMP. Import from `@optimizely/cms-sdk`.

## Setup

```typescript
import { damAssets } from '@optimizely/cms-sdk';

export default function MyComponent({ content }) {
  const { getSrcset, getAlt, isDamImageAsset, isDamVideoAsset, isDamRawFileAsset, isDamAsset, getDamAssetType } = damAssets(content);
  // ...
}
```

The `damAssets(content)` function takes the content object and returns helpers that automatically include preview tokens when in edit mode.

## Functions

### `getSrcset(property)`

Creates a responsive `srcset` string from image renditions. Handles deduplication and preview tokens automatically.

```typescript
const { getSrcset } = damAssets(content);

<img
  src={content.heroImage?.item?.Url}
  srcSet={getSrcset(content.heroImage)}
  sizes="(max-width: 768px) 100vw, 50vw"
/>
```

**Returns:** `string | undefined` — srcset string like `"url1 100w, url2 500w"`, or `undefined` if no renditions

### `getAlt(property, fallback?)`

Gets alt text for an image or video asset.

```typescript
const { getAlt } = damAssets(content);

// Uses AltText from asset, falls back to provided text
<img alt={getAlt(content.heroImage, 'Hero image')} />

// Returns empty string (decorative image) if no AltText
<img alt={getAlt(content.decorativeIcon)} />
```

**Parameters:**
- `property` — Content reference (InferredContentReference)
- `fallback?: string` — Fallback text if no AltText on asset (default: `""`)

**Returns:** `string` — Alt text, fallback, or empty string

### `isDamImageAsset(property)`

Type guard: checks if a content reference is an image asset (`cmp_PublicImageAsset`). Narrows the TypeScript type.

```typescript
const { isDamImageAsset } = damAssets(content);

if (isDamImageAsset(content.media)) {
  // TypeScript knows content.media.item is PublicImageAsset
  const width = content.media.item.Width;
  const height = content.media.item.Height;
  const altText = content.media.item.AltText;
  const renditions = content.media.item.Renditions;
  const focalPoint = content.media.item.FocalPoint;
}
```

### `isDamVideoAsset(property)`

Type guard: checks if a content reference is a video asset (`cmp_PublicVideoAsset`).

```typescript
const { isDamVideoAsset } = damAssets(content);

if (isDamVideoAsset(content.media)) {
  // TypeScript knows content.media.item is PublicVideoAsset
  const videoUrl = content.media.item.Url;
  const altText = content.media.item.AltText;
}
```

### `isDamRawFileAsset(property)`

Type guard: checks if a content reference is a raw file asset (`cmp_PublicRawFileAsset`).

```typescript
const { isDamRawFileAsset } = damAssets(content);

if (isDamRawFileAsset(content.media)) {
  // TypeScript knows content.media.item is PublicRawFileAsset
  const fileUrl = content.media.item.Url;
  const mimeType = content.media.item.MimeType;
}
```

### `isDamAsset(property)`

Checks if a content reference is any type of DAM asset.

```typescript
const { isDamAsset } = damAssets(content);

if (!isDamAsset(content.media)) {
  return <div>No media uploaded</div>;
}
```

### `getDamAssetType(property)`

Returns the asset type as a string literal.

```typescript
const { getDamAssetType } = damAssets(content);
const type = getDamAssetType(content.media);
// Returns: 'image' | 'video' | 'file' | 'unknown'
```

## Asset Type Shapes

### PublicImageAsset

```typescript
{
  __typename: 'cmp_PublicImageAsset';
  Url: string | null;
  Title: string | null;
  Description: string | null;
  Tags: { Guid: string | null; Name: string | null }[] | null;
  MimeType: string | null;
  Height: number | null;
  Width: number | null;
  AltText: string | null;
  Renditions: { Id, Name, Url, Width, Height }[] | null;
  FocalPoint: { X: number | null; Y: number | null } | null;
}
```

### PublicVideoAsset

```typescript
{
  __typename: 'cmp_PublicVideoAsset';
  Url: string | null;
  Title: string | null;
  Description: string | null;
  Tags: { Guid, Name }[] | null;
  MimeType: string | null;
  AltText: string | null;
  Renditions: { Id, Name, Url, Width, Height }[] | null;
}
```

### PublicRawFileAsset

```typescript
{
  __typename: 'cmp_PublicRawFileAsset';
  Url: string | null;
  Title: string | null;
  Description: string | null;
  Tags: { Guid, Name }[] | null;
  MimeType: string | null;
}
```

## Complete Example: Multi-Asset Component

```typescript
import { contentType, ContentProps, damAssets } from '@optimizely/cms-sdk';

export const MediaBlockCT = contentType({
  key: 'MediaBlock',
  baseType: '_component',
  compositionBehaviors: ['sectionEnabled'],
  properties: {
    media: { type: 'contentReference', displayName: 'Media' },
    caption: { type: 'string', displayName: 'Caption' },
  },
});

type Props = { content: ContentProps<typeof MediaBlockCT> };

export default function MediaBlock({ content }: Props) {
  const { getSrcset, getAlt, getDamAssetType, isDamImageAsset } = damAssets(content);

  switch (getDamAssetType(content.media)) {
    case 'image':
      return (
        <figure>
          <img
            src={content.media?.item?.Url ?? ''}
            srcSet={getSrcset(content.media)}
            sizes="(max-width: 768px) 100vw, 50vw"
            alt={getAlt(content.media, content.caption ?? '')}
          />
          {content.caption && <figcaption>{content.caption}</figcaption>}
        </figure>
      );
    case 'video':
      return <video src={content.media?.item?.Url ?? ''} controls />;
    case 'file':
      return (
        <a href={content.media?.item?.Url ?? ''} download>
          {content.media?.item?.Title || 'Download'}
        </a>
      );
    default:
      return <p>No media</p>;
  }
}
```
