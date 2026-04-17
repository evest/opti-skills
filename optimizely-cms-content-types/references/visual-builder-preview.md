# Visual Builder Preview Setup

For Visual Builder to work, you need three things: SDK registry initialization, experience components, and a preview route.

## 1. SDK Registry Initialization

Create `src/optimizely.ts` and import it in your root layout:

```typescript
import {
  initContentTypeRegistry,
  initDisplayTemplateRegistry,
  BlankExperienceContentType,
  BlankSectionContentType,
} from '@optimizely/cms-sdk';
import { initReactComponentRegistry } from '@optimizely/cms-sdk/react/server';

// MUST include BlankExperienceContentType and BlankSectionContentType
initContentTypeRegistry([
  BlankExperienceContentType,
  BlankSectionContentType,
  // ... your content types
]);

initReactComponentRegistry({
  resolver: {
    BlankExperience,  // React component for experiences
    BlankSection,     // React component for sections
    // ... your components
  },
});
```

## 2. Experience Components

Create `BlankExperience` and `BlankSection` React components. See `troubleshooting.md` for complete examples.

## 3. Preview Route

Create `app/preview/page.tsx`:

```typescript
import { GraphClient, type PreviewParams } from '@optimizely/cms-sdk';
import { OptimizelyComponent } from '@optimizely/cms-sdk/react/server';
import { PreviewComponent } from '@optimizely/cms-sdk/react/client';
import Script from 'next/script';

export default async function PreviewPage({ searchParams }: Props) {
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: process.env.OPTIMIZELY_GRAPH_GATEWAY,
  });

  const response = await client.getPreviewContent(
    (await searchParams) as PreviewParams
  );

  return (
    <div>
      <Script
        src={`${process.env.OPTIMIZELY_CMS_URL}/util/javascript/communicationinjector.js`}
        strategy="afterInteractive"
      />
      <PreviewComponent />
      <OptimizelyComponent content={response} />
    </div>
  );
}
```

## Required Environment Variables

```bash
OPTIMIZELY_CMS_URL=https://app-xxx.cms.optimizely.com
OPTIMIZELY_GRAPH_GATEWAY=https://cg.optimizely.com/content/v2  # Include full path!
OPTIMIZELY_GRAPH_SINGLE_KEY=your-single-key
```
