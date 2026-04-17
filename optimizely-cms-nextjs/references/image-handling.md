# Image Handling

The starter ships a custom Cloudinary loader plus `next/image` `remotePatterns` covering the Optimizely DAM hosts.

## `next.config.ts` image config

```ts
images: {
  remotePatterns: [
    { protocol: 'https', hostname: '*.cms.optimizely.com' },
    { protocol: 'https', hostname: '*.cmstest.optimizely.com' },
    { protocol: 'https', hostname: '*.optimizely.com', port: '', pathname: '/**' },
    { protocol: 'https', hostname: 'res.cloudinary.com' },
  ],
  loader: 'custom',
  loaderFile: './lib/image/loader.ts',
}
```

## Custom loader

```ts
// lib/image/loader.ts
'use client'

const CLOUDINARY_REGEX =
  /^.+\.cloudinary\.com\/([^/]+)\/(?:(image|video|raw)\/)?(?:(upload|fetch|private|authenticated|sprite|facebook|twitter|youtube|vimeo)\/)?(?:(?:[^/]+\/[^,/]+,?)*\/)?(?:v(\d+|\w{1,2})\/)?([^.^\s]+)(?:\.(.+))?$/

export const extractCloudinaryPublicID = (link: string): string => {
  if (!link) return ''
  const parts = CLOUDINARY_REGEX.exec(link)
  if (parts && parts.length > 2) {
    const path = parts[parts.length - 2]
    const extension = parts[parts.length - 1]
    return `${path}${extension ? '.' + extension : ''}`
  }
  return link
}

const extractCloudName = (link: string): string => {
  const parts = CLOUDINARY_REGEX.exec(link)
  return parts && parts.length > 2 && parts[1] ? parts[1] : link
}

const getParams = (path: string, width: number, quality?: number) => {
  const params = path.toLowerCase().endsWith('.svg')
    ? []
    : [`f_auto`, `c_limit`, `w_${width || 'auto'}`, `q_${quality || 'auto'}`]
  return params.length ? `/${params.join(',')}/` : '/'
}

const paramFormats = ['f_', 'c_']

export default function cloudinaryLoader({
  src, width, quality,
}: { src: string; width: number; quality?: number }) {
  if (src.startsWith('https://res.cloudinary.com')) {
    if (paramFormats.some((f) => src.includes(f))) return src   // already optimized
    const publicId = extractCloudinaryPublicID(src)
    if (!publicId) return src
    const cloudName = extractCloudName(src)
    const params = getParams(publicId, width, quality)
    return `https://res.cloudinary.com/${cloudName}/image/upload${params}${publicId}`
  }
  return src
}
```

## What this does

For a plain Cloudinary URL like `https://res.cloudinary.com/demo/image/upload/sample.jpg`:

1. Detects it starts with `res.cloudinary.com`.
2. Extracts the cloud name (`demo`) and public ID (`sample.jpg`).
3. Generates transformation params:
   - `f_auto` — auto format (WebP/AVIF where supported)
   - `c_limit` — don't upscale
   - `w_<width>` — width picked by Next.js's `sizes` logic
   - `q_auto` (or `q_<quality>`) — auto quality
4. Returns `https://res.cloudinary.com/demo/image/upload/f_auto,c_limit,w_800,q_auto/sample.jpg`.

For SVGs (detected by `.svg` suffix), no transformation params are added — optimization would damage vector images.

For Cloudinary URLs that already contain transformation params (detected by `f_` or `c_` substring), the loader returns the URL unchanged. Avoids double-transforming editor-managed URLs.

For any non-Cloudinary URL (including `*.cms.optimizely.com`), the loader returns the src unchanged — those hosts serve their own optimized images.

## `'use client'` directive

The loader file is marked `'use client'` because Next.js's custom loader executes in the browser (the rendered `<img src>` values are built at request time on the server, but resolved client-side for responsive `srcSet` generation). Do NOT add server-only imports (`fs`, `cookies`, etc.) — they'll break the bundle.

## Using `next/image` with CMS images

```tsx
import Image from 'next/image'

// In a block component:
<Image
  src={imageSrc}                // CMS-provided URL (Cloudinary or Optimizely DAM)
  alt={altText ?? ''}
  fill                          // or width/height
  className="object-cover"
/>
```

The loader runs per image, per rendered width. Next.js generates the `srcSet` covering its default breakpoints. For very precise control, pass `sizes` to narrow which widths get generated.

## DAM assets from the SDK

For Optimizely DAM assets, use the `damAssets()` helpers (see content-types skill):

```tsx
import { damAssets } from '@optimizely/cms-sdk'

export default function HeroBlock({ content }: Props) {
  const { getSrcset, getAlt, isDamImageAsset } = damAssets(content)

  if (content.backgroundImage && isDamImageAsset(content.backgroundImage)) {
    return (
      <img
        src={content.backgroundImage.item.Url}
        srcSet={getSrcset(content.backgroundImage)}
        alt={getAlt(content.backgroundImage, 'Hero')}
      />
    )
  }
  return null
}
```

`damAssets()` produces SDK-native `srcSet` strings keyed on DAM rendition widths. Use it when the content property is a `contentReference` to a DAM asset; use the Next.js Image + custom loader combo for plain Cloudinary URL strings.

## Adding a new CDN host

1. Add the hostname to `remotePatterns` in `next.config.ts`.
2. If the CDN needs custom transformation (like Cloudinary), extend `loader.ts`:
   ```ts
   if (src.startsWith('https://my-cdn.example.com')) {
     // ... build transformed URL
     return transformed
   }
   ```
3. Keep the "return src unchanged" fallback at the bottom — any unhandled host passes through.

## Debugging

- **Images don't load** → check browser console for `remotePatterns` violation; add the hostname.
- **Images are blurry** → the loader might be returning a URL with no params; verify the regex matches your Cloudinary URL shape.
- **Editor-provided Cloudinary URLs render twice-optimized** → check the `paramFormats` short-circuit; editor URLs often already contain `f_auto`.
- **SVGs are being compressed into raster** → ensure the `.svg` extension check in `getParams` works for your filename (lowercase compare).
