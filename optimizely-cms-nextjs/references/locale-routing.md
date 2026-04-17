# Locale Routing (`proxy.ts` middleware)

The starter uses a single middleware file at repo root named `proxy.ts` (not `middleware.ts`). It handles every request, negotiates the locale, and rewrites or redirects to a locale-prefixed path.

## Why `proxy.ts` not `middleware.ts`

Next.js supports both — `middleware.ts` is the default convention; `proxy.ts` is valid when the middleware is configured to load from that path. The starter uses `proxy.ts` because of its separation-of-concerns convention. Do not rename without updating `next.config.ts` and all imports. The file exports:

- `export async function proxy(request)` — named export
- `export const config = { matcher: [...] }`

That pairing is what Next.js looks for, regardless of the filename.

## Locale priority

```
1. Locale in URL path       (e.g. /pl/about)           — user intent, strongest signal
2. Cookie  __LOCALE_NAME    (previously-chosen locale) — durable preference
3. Accept-Language header   (parsed by Negotiator)      — browser preference
4. DEFAULT_LOCALE           ('en')                      — fallback
```

The principle: **user intent beats browser preference**. A link to `/pl/about` shared with a Swedish-speaking user should display Polish content, not silently flip to Swedish just because `Accept-Language` says so. The URL path wins unconditionally.

Default locale uses **rewrite** (URL stays `/about`, server sees `/en/about`). Non-default uses **redirect** (URL changes to `/pl/about`). Rationale: canonical URLs for the default language should be clean; non-default needs an explicit marker so users can share links.

### Silent fallback on missing translations

Optimizely Graph serves content in a fallback locale (usually the CMS instance's default) when the requested locale has no translated version. This happens **silently** — no error, no log, no visible marker. A Swedish visitor requesting a page only translated into English will see the English version at `/sv/page-name`.

This is usually desirable (better than a 404), but it's easy to miss during QA. Verify translation coverage manually or add a runtime check (`content._metadata.locale !== requestedLocale`) to log fallbacks.

## Full file

```ts
// proxy.ts
import { DEFAULT_LOCALE, LOCALES } from '@/lib/optimizely/language'
import { createUrl, leadingSlashUrlPath } from '@/lib/utils'
import type { NextRequest } from 'next/server'
import { NextResponse } from 'next/server'
import Negotiator from 'negotiator'

const COOKIE_NAME_LOCALE = '__LOCALE_NAME'
const HEADER_KEY_LOCALE  = 'X-Locale'

function shouldExclude(path: string) {
  return (
    path.startsWith('/static') ||
    path.includes('/api/') ||
    path.includes('.') ||          // skip files (favicon, images, etc.)
    path.includes('/json') ||
    path.includes('/preview')      // preview route bypasses locale negotiation
  )
}

function getBrowserLanguage(request: NextRequest, locales: string[]): string | undefined {
  const headerLanguage = request.headers.get('Accept-Language')
  if (!headerLanguage) return undefined

  const languages = new Negotiator({
    headers: { 'accept-language': headerLanguage },
  }).languages()

  for (const lang of languages) {
    if (locales.includes(lang)) return lang                    // exact match
    const prefix = lang.split('-')[0]                           // strip region
    if (locales.includes(prefix)) return prefix                 // 'pl-PL' → 'pl'
  }
  return undefined
}

function getLocale(request: NextRequest, locales: string[]): string {
  const cookieLocale = request.cookies.get(COOKIE_NAME_LOCALE)?.value
  if (cookieLocale && locales.includes(cookieLocale)) return cookieLocale

  const browserLang = getBrowserLanguage(request, locales)
  if (browserLang && locales.includes(browserLang)) return browserLang

  return DEFAULT_LOCALE
}

function updateLocaleCookies(
  request: NextRequest, response: NextResponse, locale?: string,
): void {
  const cookieLocale = request.cookies.get(COOKIE_NAME_LOCALE)?.value
  const newLocale = locale || null

  if (newLocale !== cookieLocale) {
    if (newLocale) response.cookies.set(COOKIE_NAME_LOCALE, newLocale)
    else           response.cookies.delete(COOKIE_NAME_LOCALE)
  }

  if (newLocale) response.headers.append(HEADER_KEY_LOCALE, newLocale)
  else           response.headers.delete(HEADER_KEY_LOCALE)
}

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname
  let response = NextResponse.next()

  if (shouldExclude(pathname)) return response

  // Case 1: URL already contains a known locale → rewrite to normalized form
  const localeInPathname = LOCALES.find(
    (l) => pathname.startsWith(`/${l}/`) || pathname === `/${l}`,
  )
  if (localeInPathname) {
    const pathnameWithoutLocale = pathname.replace(`/${localeInPathname}`, '')
    const newUrl = createUrl(
      `/${localeInPathname}${leadingSlashUrlPath(pathnameWithoutLocale)}`,
      request.nextUrl.searchParams,
    )
    response = NextResponse.rewrite(new URL(newUrl, request.url))
    updateLocaleCookies(request, response, localeInPathname)
    return response
  }

  // Case 2: No locale in URL → negotiate and either rewrite (default) or redirect (non-default)
  const locale = getLocale(request, LOCALES)
  const newUrl = createUrl(
    `/${locale}${leadingSlashUrlPath(pathname)}`,
    request.nextUrl.searchParams,
  )
  response =
    locale === DEFAULT_LOCALE
      ? NextResponse.rewrite(new URL(newUrl, request.url))
      : NextResponse.redirect(new URL(newUrl, request.url))

  updateLocaleCookies(request, response, locale)
  return response
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
}
```

## What the matcher excludes

- `api/*` — API routes (including `/api/revalidate`)
- `_next/static/*` — bundled JS/CSS
- `_next/image` — Next.js image optimization endpoint
- `favicon.ico`

Plus the `shouldExclude()` checks further narrow excluded paths at function-level: anything with a `.`, `/static`, `/api/`, `/json`, or `/preview`. The redundancy is intentional — the matcher excludes at the edge; `shouldExclude` is the authoritative check.

## Cookie vs Accept-Language precedence

Cookie wins over Accept-Language, so once a user has clicked the language-switcher their choice persists across sessions. The cookie is set on every matched request (see `updateLocaleCookies`) so even implicit locale detections via Accept-Language get written back as a preference.

## Language switcher (client component)

```tsx
// components/layout/language-switcher.tsx  (abbreviated)
'use client'
import { useRouter, usePathname } from 'next/navigation'
import { LOCALES } from '@/lib/optimizely/language'

const LOCALE_NAMES = { en: 'English', pl: 'Polski', sv: 'Svenska' } as const

export function LanguageSwitcher({ currentLocale }: { currentLocale: string }) {
  const router = useRouter()
  const pathname = usePathname()

  function switchTo(next: string) {
    // Replace leading /<old>/ with /<new>/
    const stripped = pathname.replace(new RegExp(`^/${currentLocale}(/|$)`), '/')
    const target = next === currentLocale ? pathname : `/${next}${stripped}`
    router.push(target)
    router.refresh()
  }

  return (
    <select value={currentLocale} onChange={(e) => switchTo(e.target.value)}>
      {LOCALES.map((l) => <option key={l} value={l}>{LOCALE_NAMES[l]}</option>)}
    </select>
  )
}
```

The switcher does a `router.push` to the locale-prefixed URL. The middleware will then:
- If `next` is the default locale → rewrite to the internal `/en/...` form (URL stays clean? No — because `router.push(target)` directly uses `target` which already has the prefix; the middleware's "non-default" redirect logic doesn't apply because the URL already starts with a known locale).
- Either way, the `__LOCALE_NAME` cookie gets updated so future bare URLs render in the new locale.

## hreflang — `generateAlternates`

Every page's `generateMetadata()` returns `alternates` so crawlers understand multi-lingual equivalents.

```ts
// lib/metadata.ts
import { LOCALES } from '@/lib/optimizely/language'
import { AlternateURLs } from 'next/dist/lib/metadata/types/alternative-urls-types'

export function normalizePath(path: string): string {
  path = path.toLowerCase()
  if (path === '/')        return ''
  if (path.endsWith('/'))  path = path.slice(0, -1)
  if (path.startsWith('/')) path = path.slice(1)
  return path
}

export function generateAlternates(locale: string, path: string): AlternateURLs {
  path = normalizePath(path)
  return {
    canonical: `/${locale}/${path}`,
    languages: Object.assign(
      {},
      ...LOCALES.map((l) => ({ [l]: `/${l}/${path}` })),
    ),
  }
}
```

Usage:
```ts
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale, slug } = await params
  return {
    ...
    alternates: generateAlternates(locale, `/${slug.join('/')}/`),
  }
}
```

Produces `<link rel="alternate" hreflang="en" href="/en/about">` etc. alongside the canonical.

## Adding a new locale

1. Add to `LOCALES` in `lib/optimizely/language.ts`.
2. Add its display name in `components/layout/language-switcher.tsx`'s `LOCALE_NAMES` map.
3. In Optimizely CMS: Settings → Languages → add the new language.
4. Publish content in that language for every CMS page you want available.

No middleware changes needed — `Negotiator` picks up whatever's in `LOCALES`, and `generateStaticParams` in the locale layout uses `LOCALES` directly.

## Debugging middleware

- Add `console.log` liberally in `proxy.ts` — logs land in the dev server output (not the browser).
- The `X-Locale` response header (written by `updateLocaleCookies`) is a cheap verification that middleware ran and chose the right locale.
- If `/api/revalidate` behaves strangely, confirm the matcher actually excludes it — a misconfigured matcher that routes API requests through the middleware will rewrite them to `/en/api/...` and they'll 404.
