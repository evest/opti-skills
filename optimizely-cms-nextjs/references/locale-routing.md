# Locale Routing (`next-intl` + `src/proxy.ts`)

This project uses `next-intl` for locale routing — no bespoke Negotiator setup, no custom rewrite logic. The middleware lives at `src/proxy.ts` (Next.js auto-detects the proxy export + config; filename `middleware.ts` would also work).

## The three i18n files

```
src/i18n/
  routing.ts        — defineRouting({ locales, defaultLocale, localePrefix })
  request.ts        — getRequestConfig wraps async config + messages import
  navigation.ts     — createNavigation(routing) — locale-aware Link, redirect, etc.
```

### `routing.ts`

```ts
// src/i18n/routing.ts
import { defineRouting } from 'next-intl/routing';

export const routing = defineRouting({
  locales: ['en', 'no', 'sv', 'da'] as const,
  defaultLocale: 'no',
  localePrefix: 'always',
});

export type Locale = (typeof routing.locales)[number];
```

`localePrefix: 'always'` means every URL is locale-prefixed — there's no bare `/about`, it's always `/no/about` or `/en/about`. This is what makes the catch-all `src/app/[locale]/[[...slug]]` straightforward: the locale segment is always present.

The default locale (`'no'` here) is what the middleware redirects to when no locale matches.

### `request.ts`

```ts
// src/i18n/request.ts
import { hasLocale } from 'next-intl';
import { getRequestConfig } from 'next-intl/server';
import { routing } from './routing';

export default getRequestConfig(async ({ requestLocale }) => {
  const requested = await requestLocale;
  const locale = hasLocale(routing.locales, requested) ? requested : routing.defaultLocale;

  return {
    locale,
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
```

This is what `createNextIntlPlugin('./src/i18n/request.ts')` wires into the build. The dynamic import of the JSON file is what `next-intl` watches for translation file changes during dev.

### `navigation.ts`

```ts
// src/i18n/navigation.ts
import { createNavigation } from 'next-intl/navigation';
import { routing } from './routing';

export const { Link, redirect, usePathname, useRouter, getPathname } =
  createNavigation(routing);
```

Always use these instead of importing from `next/link` or `next/navigation`:
- `Link` auto-prefixes the current locale (or the explicit `locale` prop)
- `usePathname` strips the locale prefix
- `redirect` accepts both paths with and without locale

```tsx
import { Link } from '@/i18n/navigation';

<Link href="/about">About</Link>                       // → /no/about (or current locale)
<Link href="/about" locale="en">English</Link>         // → /en/about
```

## The middleware

```ts
// src/proxy.ts
import createMiddleware from 'next-intl/middleware';
import { routing } from './i18n/routing';

export default createMiddleware(routing);

export const config = {
  matcher: [
    '/((?!api|hooks|debug|diagnostics|preview|_next|_vercel|.*\\..*).*)',
  ],
};
```

That's the whole file. `createMiddleware(routing)` does everything: locale negotiation from `Accept-Language`, redirect to the prefixed URL, cookie persistence of the chosen locale.

### What the matcher excludes

- `api` — Next.js API routes
- `hooks` — the `/hooks/graph` webhook receiver
- `debug`, `diagnostics` — dev-only inspection routes (excluded from middleware AND robots)
- `preview` — the CMS preview iframe; locale negotiation would break the editor's communication
- `_next`, `_vercel` — Next.js / Vercel internals
- `.*\\..*` — any path with a file extension (skips images, JSON, etc.)

Forgetting one of these is a silent failure source:
- Forgetting `hooks` → webhook URLs get locale-prefixed → CMS sees 404, retries until quota burnt
- Forgetting `preview` → CMS iframe sees a redirect → editor screen blanks
- Forgetting `api` → API routes redirect → callers see 308

## Why filename `proxy.ts` and not `middleware.ts`

Next.js supports both — `middleware.ts` is the documented convention; `proxy.ts` works when the file exports a default function and a named `config`. The repo uses `proxy.ts` for separation-of-concerns convention. Either works; the choice is cosmetic.

If renaming, just rename the file. No `next.config.ts` changes needed — Next.js scans for either filename.

## Locale layout

```tsx
// src/app/[locale]/layout.tsx
import { notFound } from 'next/navigation';
import { hasLocale, NextIntlClientProvider } from 'next-intl';
import { setRequestLocale } from 'next-intl/server';
import { Header, Footer } from '@/components/layout';
import { routing } from '@/i18n/routing';

type Props = {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
};

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: Props) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();
  setRequestLocale(locale);

  return (
    <NextIntlClientProvider>
      <Header />
      <main id="main-content" className="flex-1">{children}</main>
      <Footer />
    </NextIntlClientProvider>
  );
}
```

Three things happen here:
1. **`hasLocale` guard** — rejects unknown locale segments (e.g. someone visiting `/fr/about` when `fr` isn't in `routing.locales`). `notFound()` commits 404.
2. **`setRequestLocale`** — tells `next-intl` what locale this server render is for. Required for static rendering; without it, `next-intl` falls back to dynamic.
3. **`<NextIntlClientProvider>`** — makes the active locale + messages available to client components. Server components use `useTranslations()` or `getTranslations()` directly.

## Reading the locale

In server components / actions:
```ts
import { getLocale, getTranslations } from 'next-intl/server';

const locale = await getLocale();
const t = await getTranslations('Header');
```

In client components:
```ts
'use client';
import { useLocale, useTranslations } from 'next-intl';

const locale = useLocale();
const t = useTranslations('Header');
```

In the SDK preview route, `useLocale`/`getLocale` is unavailable until the `NextIntlClientProvider` wraps things — that's why the preview route bridges the CMS `loc` searchParam into `setRequestLocale` manually before rendering anything else.

## Messages files

```
messages/
  en.json
  no.json
  sv.json
  da.json
```

JSON shape is namespaced — `useTranslations('Header')` resolves to the `Header` key:

```json
{
  "Header": {
    "nav": {
      "services": { "label": "Services", "href": "/services" }
    }
  }
}
```

Adding a new translation key requires updating every locale file. There's no automated check; missing keys log a warning at render time but don't fail the build.

## Adding a new locale

1. **Extend `routing.locales`** in `src/i18n/routing.ts`:
   ```ts
   locales: ['en', 'no', 'sv', 'da', 'fi'] as const,
   ```
2. **Add `messages/fi.json`** — copy from an existing locale and translate.
3. **Add the language in CMS Settings → Languages** so editors can author content in it.
4. **Translate content for every CMS page** you want available in the new locale.

No middleware changes needed — `createMiddleware(routing)` reads the locales list at call time.

## The preview route locale bridge

`/preview` is excluded from the middleware (CMS sends its own `loc` searchParam). The preview page bridges that into `next-intl` manually:

```tsx
async function PreviewBody({ searchParams }: Props) {
  const params = await searchParams;
  const locParam = typeof params.loc === 'string' ? params.loc : undefined;
  const locale = hasLocale(routing.locales, locParam) ? locParam : routing.defaultLocale;
  setRequestLocale(locale);
  const messages = (await import(`../../../messages/${locale}.json`)).default;

  // ... rest of preview render ...
  return (
    <NextIntlClientProvider locale={locale} messages={messages}>
      {/* ... */}
    </NextIntlClientProvider>
  );
}
```

The explicit `locale` and `messages` props on `<NextIntlClientProvider>` (rather than the auto-config form used in the locale layout) are necessary because the preview route lives outside `[locale]` — there's no `getRequestConfig` flow to consume.

## hreflang alternates — known TODO

The page-level `generateMetadata` in `[[...slug]]/page.tsx` intentionally omits `alternates.languages` for now:

```ts
// TODO (Phase 6c): surface alternate URLs from the CMS payload and emit
// `alternates.languages`. Localized slugs differ per locale (e.g. /no/om-oss
// vs /en/about) and the CMS owns the mapping.
```

The Graph payload exposes the current locale's URL but not its sibling-locale counterparts. Emitting `alternates.languages` correctly requires either:
- A follow-up Graph query keyed by content id, fetching every locale's URL, OR
- An explicit per-content "Alternate URLs" property in the CMS schema

Skip until one of those is in place; emitting wrong alternates is worse than emitting none.

## Locale switcher (client component)

```tsx
// src/components/layout/LocaleSwitcher.tsx (abbreviated)
'use client';
import { useLocale } from 'next-intl';
import { useRouter, usePathname } from '@/i18n/navigation';
import { routing } from '@/i18n/routing';

export default function LocaleSwitcher() {
  const currentLocale = useLocale();
  const router = useRouter();
  const pathname = usePathname();

  function switchTo(next: string) {
    router.replace(pathname, { locale: next });
  }

  return (
    <select value={currentLocale} onChange={(e) => switchTo(e.target.value)}>
      {routing.locales.map((l) => <option key={l} value={l}>{l.toUpperCase()}</option>)}
    </select>
  );
}
```

`useRouter` from `@/i18n/navigation` (not `next/navigation`) — it accepts the `locale` option and constructs the prefixed URL correctly.

## Debugging middleware

- Add `console.log` to the relevant code path. `createMiddleware` is opaque; if you need to inspect what it does, the dev server logs requests through the middleware.
- Confirm the `matcher` excludes the path you're investigating. A misconfigured matcher that routes API/webhook traffic through middleware will rewrite POST bodies and cause 308 redirects.
- The `x-pathname` and `x-next-intl-locale` response headers (when present) confirm middleware ran.

## Anti-patterns

- **Importing `Link` from `next/link`** in app code — bypasses locale prefixing. Always use `@/i18n/navigation`.
- **Hardcoding locale strings in URLs** — `<Link href="/no/about">` works but breaks for non-default locales. Use relative paths like `<Link href="/about">` and let next-intl prefix.
- **Reading `useLocale()` outside `<NextIntlClientProvider>`** — throws. Either wrap or use `getLocale()` in a server component.
- **Forgetting `setRequestLocale(locale)` in the locale layout** — falls back to dynamic rendering, defeats `cacheComponents`.
