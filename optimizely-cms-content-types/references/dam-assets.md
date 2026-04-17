# DAM Asset Helpers Reference

The `damAssets` utility provides helper functions for working with Digital Asset Management (DAM) assets from Optimizely CMP. Import from `@optimizely/cms-sdk`.

## Setup

```typescript
import { damAssets } from '@optimizely/cms-sdk';

export default function MyComponent({ opti }) {
  const { getSrcset, getAlt, isDamImageAsset, isDamVideoAsset, isDamRawFileAsset, isDamAsset, getDamAssetType } = damAssets(opti);
  // ...
}
```

The `damAssets(content)` function takes the content object and returns helpers that automatically include preview tokens when in edit mode.

## Functions

### `getSrcset(property)`

Creates a responsive `srcset` string from image renditions. Handles deduplication and preview tokens automatically.

```typescript
const { getSrcset } = damAssets(opti);

<img
  src={opti.heroImage?.item?.Url}
  srcSet={getSrcset(opti.heroImage)}
  sizes="(max-width: 768px) 100vw, 50vw"
/>
```

**Returns:** `string | undefined` — srcset string like `"url1 100w, url2 500w"`, or `undefined` if no renditions

### `getAlt(property, fallback?)`

Gets alt text for an image or video asset.

```typescript
const { getAlt } = damAssets(opti);

// Uses AltText from asset, falls back to provided text
<img alt={getAlt(opti.heroImage, 'Hero image')} />

// Returns empty string (decorative image) if no AltText
<img alt={getAlt(opti.decorativeIcon)} />
```

**Parameters:**
- `property` — Content reference (InferredContentReference)
- `fallback?: string` — Fallback text if no AltText on asset (default: `""`)

**Returns:** `string` — Alt text, fallback, or empty string

### `isDamImageAsset(property)`

Type guard: checks if a content reference is an image asset (`cmp_PublicImageAsset`). Narrows the TypeScript type.

```typescript
const { isDamImageAsset } = damAssets(opti);

if (isDamImageAsset(opti.media)) {
  // TypeScript knows opti.media.item is PublicImageAsset
  const width = opti.media.item.Width;
  const height = opti.media.item.Height;
  const altText = opti.media.item.AltText;
  const renditions = opti.media.item.Renditions;
  const focalPoint = opti.media.item.FocalPoint;
}
```

### `isDamVideoAsset(property)`

Type guard: checks if a content reference is a video asset (`cmp_PublicVideoAsset`).

```typescript
const { isDamVideoAsset } = damAssets(opti);

if (isDamVideoAsset(opti.media)) {
  // TypeScript knows opti.media.item is PublicVideoAsset
  const videoUrl = opti.media.item.Url;
  const altText = opti.media.item.AltText;
}
```

### `isDamRawFileAsset(property)`

Type guard: checks if a content reference is a raw file asset (`cmp_PublicRawFileAsset`).

```typescript
const { isDamRawFileAsset } = damAssets(opti);

if (isDamRawFileAsset(opti.media)) {
  // TypeScript knows opti.media.item is PublicRawFileAsset
  const fileUrl = opti.media.item.Url;
  const mimeType = opti.media.item.MimeType;
}
```

### `isDamAsset(property)`

Checks if a content reference is any type of DAM asset.

```typescript
const { isDamAsset } = damAssets(opti);

if (!isDamAsset(opti.media)) {
  return <div>No media uploaded</div>;
}
```

### `getDamAssetType(property)`

Returns the asset type as a string literal.

```typescript
const { getDamAssetType } = damAssets(opti);
const type = getDamAssetType(opti.media);
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

type Props = { opti: ContentProps<typeof MediaBlockCT> };

export default function MediaBlock({ opti }: Props) {
  const { getSrcset, getAlt, getDamAssetType, isDamImageAsset } = damAssets(opti);

  switch (getDamAssetType(opti.media)) {
    case 'image':
      return (
        <figure>
          <img
            src={opti.media?.item?.Url ?? ''}
            srcSet={getSrcset(opti.media)}
            sizes="(max-width: 768px) 100vw, 50vw"
            alt={getAlt(opti.media, opti.caption ?? '')}
          />
          {opti.caption && <figcaption>{opti.caption}</figcaption>}
        </figure>
      );
    case 'video':
      return <video src={opti.media?.item?.Url ?? ''} controls />;
    case 'file':
      return (
        <a href={opti.media?.item?.Url ?? ''} download>
          {opti.media?.item?.Title || 'Download'}
        </a>
      );
    default:
      return <p>No media</p>;
  }
}
```
