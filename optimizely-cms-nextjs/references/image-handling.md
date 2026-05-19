# Image Handling

The Optimizely CDN serves transform-ready URLs; Next.js's default image loader handles them fine. No custom loader needed.

## `next.config.ts` image config

```ts
images: {
  remotePatterns: [
    { protocol: 'https', hostname: '*.cms.optimizely.com' },
    { protocol: 'https', hostname: 'cdn.optimizely.com' },
    { protocol: 'https', hostname: '*.cmp.optimizely.com' },
  ],
},
```

What each hostname covers:
- `*.cms.optimizely.com` — CMS instance image URLs (uploaded media)
- `cdn.optimizely.com` — Optimizely's shared CDN
- `*.cmp.optimizely.com` — Content Marketing Platform DAM hosts (PublicImageAsset, PublicVideoAsset, PublicRawFileAsset)

Without a `loader` / `loaderFile` setting, Next.js uses its built-in image optimizer — works correctly against Optimizely-hosted images.

## Using `next/image` with CMS images

The pattern:
```tsx
import Image from 'next/image';
import { damAssets } from '@optimizely/cms-sdk';
import { getPreviewUtils } from '@optimizely/cms-sdk/react/server';

export default function HeroBlock({ content }: Props) {
  const { src } = getPreviewUtils(content);
  const { getAlt } = damAssets(content);
  const imageUrl = src(content.backgroundImage);

  if (!imageUrl) return null;

  return (
    <Image
      src={imageUrl}
      alt={getAlt(content.backgroundImage, '')}
      fill
      className="object-cover"
      sizes="100vw"
      priority
    />
  );
}
```

Three SDK helpers do most of the work:
- `getPreviewUtils(content).src(reference)` — resolves the URL and appends preview tokens in edit mode
- `damAssets(content).getAlt(reference, fallback)` — reads `AltText` from the DAM asset with fallback
- `damAssets(content).getSrcset(reference)` — generates a `srcSet` from DAM renditions (use this in plain `<img>` for responsive renditions when Next.js's auto srcSet isn't enough)

Detailed DAM helper reference lives in the `optimizely-cms-content-types` skill (`references/dam-assets.md`).

## Why no custom loader

This project deliberately does NOT use a custom Next.js image loader. Reasons:

1. **Optimizely-hosted images are already CDN-optimized.** The CDN URL format includes query-string transforms; Next.js's default optimizer correctly handles the responsive `sizes` story by passing through width hints.
2. **The DAM helpers (`getSrcset`) handle responsive rendering when you want SDK-aware behaviour.** Falling back to plain `<img>` with a manual `srcSet` is the escape hatch.
3. **No Cloudinary or other third-party CDN in the asset pipeline.** Adding a custom loader would be premature complexity.

If you add a third-party CDN (e.g. Cloudinary, Imgix) later, you can:
- Add the hostname to `remotePatterns` and let Next.js's default optimizer handle it
- Or write a custom loader at `src/lib/image/loader.ts` and set `images.loader: 'custom'` + `images.loaderFile`. The loader runs client-side (`'use client'`); do not add server-only imports.

Skeleton for a future Cloudinary loader:
```ts
// src/lib/image/loader.ts
'use client';

export default function imageLoader({ src, width, quality }: {
  src: string; width: number; quality?: number;
}) {
  if (src.startsWith('https://res.cloudinary.com')) {
    // transform into f_auto,c_limit,w_<width>,q_<quality> form
  }
  return src;
}
```

Don't add this prematurely. Add when the asset source requires it.

## SVG handling

`next/image` rejects SVGs by default (security: SVG can contain scripts). Two options:

1. Use plain `<img>` for SVG assets:
   ```tsx
   <img src={src(content.icon)} alt={getAlt(content.icon, '')} />
   ```
2. Enable `dangerouslyAllowSVG` in `next.config.ts` (only if you trust the asset source — Optimizely DAM is generally safe):
   ```ts
   images: {
     dangerouslyAllowSVG: true,
     contentSecurityPolicy: "default-src 'self'; script-src 'none';",
     // ...
   }
   ```

This repo doesn't enable `dangerouslyAllowSVG` — SVG assets render via plain `<img>` from the relevant component.

## DAM assets in detail

For Optimizely DAM assets (`cmp_PublicImageAsset`, etc.), the SDK exposes type guards and helpers via `damAssets(content)`:

```tsx
import { damAssets } from '@optimizely/cms-sdk';

export default function MediaBlock({ content }: Props) {
  const { isDamImageAsset, isDamVideoAsset, getSrcset, getAlt } = damAssets(content);

  if (isDamImageAsset(content.media)) {
    return (
      <img
        src={content.media.item.Url}
        srcSet={getSrcset(content.media)}
        alt={getAlt(content.media, 'Media')}
      />
    );
  }

  if (isDamVideoAsset(content.media)) {
    return <video src={content.media.item.Url} controls />;
  }

  return null;
}
```

`getSrcset` produces an SDK-native srcSet string keyed on DAM rendition widths. Use it instead of relying on Next.js to generate variants when:
- The DAM has pre-cut renditions you want to use exactly
- You need specific widths that don't match Next.js's default breakpoints
- You're not using `next/image` (e.g. inside RichText)

Full DAM API in the content-types skill's `references/dam-assets.md`.

## Adding a new image hostname

1. Add the hostname pattern to `remotePatterns` in `next.config.ts`:
   ```ts
   { protocol: 'https', hostname: 'new-cdn.example.com' },
   ```
2. If the CDN serves transform URLs you want Next.js to respect, no further action — the default optimizer passes them through.
3. If the CDN requires URL transformation (params for `w_/q_`/etc.), write a custom loader (see "Why no custom loader" above).
4. Restart the dev server — `next.config.ts` changes don't hot-reload.

## Debugging

| Symptom | Cause | Fix |
|---|---|---|
| `next/image` throws "hostname not configured" | Hostname missing from `remotePatterns` | Add it |
| Images load but are full-resolution everywhere | `sizes` prop missing on `<Image>` | Add `sizes` so Next.js knows which widths to generate |
| Draft images don't render in preview | Component using `content.image.url.default` directly | Switch to `src(content.image)` from `getPreviewUtils` |
| SVG asset rejected | `next/image` blocks SVG by default | Use plain `<img>` or enable `dangerouslyAllowSVG` cautiously |
| DAM video doesn't play | Browser MIME check failed | Inspect `content.media.item.MimeType` — usually `video/mp4`; check `<source>` tag if used |
| `getSrcset` returns undefined | No renditions on the asset | DAM asset hasn't been processed yet; falls back to single Url |
