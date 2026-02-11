# Environment Variables Reference

Complete guide to environment variables for Optimizely Frontend Hosting.

## Overview

Environment variables in Optimizely Frontend Hosting are used at two different times:
1. **Build time**: Available during `npm run build` or `yarn build`
2. **Runtime**: Available when the Next.js application is running

## Required Deployment Credentials

These are used by PowerShell scripts to authenticate with the Optimizely Cloud Deployment API. They must be set in your local environment before running deployment scripts.

### OPTI_PROJECT_ID

**Purpose**: Identifies your specific Optimizely project

**Where to get it**: PaaS Portal > Your Frontend Project > API tab

**Format**: GUID (e.g., `2a561398-d517-4634-9bc4-aab5008a8e1a`)

**Set in**: Local environment (your machine)

**Example**:
```powershell
$env:OPTI_PROJECT_ID = "2a561398-d517-4634-9bc4-aab5008a8e1a"
```

### OPTI_CLIENT_KEY

**Purpose**: API authentication key

**Where to get it**: PaaS Portal > Your Frontend Project > API tab > Add API Credentials

**Format**: String (e.g., `dxp-abc123xyz456`)

**Set in**: Local environment (your machine)

**Example**:
```powershell
$env:OPTI_CLIENT_KEY = "dxp-abc123xyz456"
```

### OPTI_CLIENT_SECRET

**Purpose**: API authentication secret

**Where to get it**: PaaS Portal > Your Frontend Project > API tab > Add API Credentials

**Format**: String (displayed only once when created)

**Set in**: Local environment (your machine)

**Security**: Keep this secret! Don't commit to version control.

**Example**:
```powershell
$env:OPTI_CLIENT_SECRET = "your-secret-here"
```

## Automatic Runtime Variables

These variables are automatically provided by Optimizely Frontend Hosting and are available during build and runtime. You don't set these - they're injected by the platform.

### OPTIMIZELY_CMS_URL

**Purpose**: URL of the Optimizely CMS backend

**Format**: `https://app-{environment}.cms.optimizely.com/`

**Example**: `https://app-test1-myproject.cms.optimizely.com/`

**Available**: Build time and runtime

**Usage in Next.js**:
```typescript
const cmsUrl = process.env.OPTIMIZELY_CMS_URL;
```

### OPTIMIZELY_GRAPH_GATEWAY

**Purpose**: Optimizely Graph API endpoint

**Format**: `https://cg.optimizely.com/content/v2`

**Available**: Build time and runtime

**Usage in Next.js**:
```typescript
const graphEndpoint = process.env.OPTIMIZELY_GRAPH_GATEWAY;

const response = await fetch(graphEndpoint, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${process.env.OPTIMIZELY_GRAPH_SECRET}`
  },
  body: JSON.stringify({ query: graphqlQuery })
});
```

### OPTIMIZELY_GRAPH_SECRET

**Purpose**: Authentication token for Optimizely Graph API

**Format**: JWT token string

**Available**: Build time and runtime

**Security**: Never expose this in client-side code. Use only in:
- Server-side code
- API routes
- `getStaticProps` / `getServerSideProps`
- Server components (Next.js 13+ App Router)

**Usage**:
```typescript
// In API route or server component
const response = await fetch(process.env.OPTIMIZELY_GRAPH_GATEWAY, {
  headers: {
    'Authorization': `Bearer ${process.env.OPTIMIZELY_GRAPH_SECRET}`
  }
});
```

### OPTIMIZELY_GRAPH_SINGLE_KEY

**Purpose**: Single-use key for Optimizely Graph access

**Format**: String

**Available**: Build time and runtime

**Usage**: Typically used for anonymous or public access to Graph content.

### OPTIMIZELY_GRAPH_APP_KEY

**Purpose**: Application key for Optimizely Graph

**Format**: String

**Available**: Build time and runtime

**Usage**: Used to identify your application when querying Optimizely Graph.

## Custom Application Settings

You can add custom environment variables through the PaaS Portal that will be available during build and runtime.

### How to Add Custom Variables

1. Navigate to PaaS Portal
2. Select your frontend project
3. Go to **App Settings** tab
4. Click **Add Setting**
5. Enter:
   - **Name**: Variable name (e.g., `MY_API_KEY`)
   - **Value**: Variable value
   - **Environment**: Select which environment (Test1, Test2, Production)

### Common Custom Variables

```
# External API keys
NEXT_PUBLIC_ANALYTICS_ID=GA-XXXXXXXXX
STRIPE_SECRET_KEY=sk_test_xxxxx

# Feature flags
NEXT_PUBLIC_ENABLE_FEATURE_X=true
ENABLE_DEBUG_MODE=false

# Third-party services
SENDGRID_API_KEY=SG.xxxxx
AWS_BUCKET_NAME=my-bucket

# Custom configuration
MAX_ITEMS_PER_PAGE=20
CACHE_TTL_SECONDS=3600
```

### Naming Conventions

**For Next.js public variables** (exposed to browser):
- Prefix with `NEXT_PUBLIC_`
- Example: `NEXT_PUBLIC_API_URL`

**For server-only variables**:
- No prefix required
- Never accessible from browser
- Example: `DATABASE_URL`, `API_SECRET`

## Environment Variable Priority

Variables are loaded in this order (later sources override earlier ones):

1. System environment (Optimizely-provided)
2. PaaS Portal App Settings
3. `.env.production` file (if present in package)
4. Runtime environment

**Note**: `.env` files are usually excluded via `.zipignore`, so rely on PaaS Portal for production configuration.

## Build-Time vs Runtime

### Build-Time Variables

Used during `npm run build` or `yarn build`:
```typescript
// next.config.js
module.exports = {
  env: {
    API_URL: process.env.API_URL
  }
};
```

These are **baked into the build** and cannot be changed without rebuilding.

### Runtime Variables

Available when the application is running:
```typescript
// pages/api/data.ts
export default function handler(req, res) {
  const apiKey = process.env.API_KEY; // Read at runtime
  // ...
}
```

These can be changed by updating App Settings and restarting the application.

## Best Practices

### Security

1. **Never commit secrets** to version control
2. **Use App Settings** for production secrets
3. **Prefix public variables** with `NEXT_PUBLIC_`
4. **Rotate secrets** regularly
5. **Limit API credential access** to required environments only

### Configuration Management

1. **Document all variables** your application needs
2. **Set variables BEFORE deployment** to avoid build failures
3. **Use consistent naming** across environments
4. **Validate variables** in your application startup code

### Environment-Specific Values

Different values per environment:

```
# Test1
NEXT_PUBLIC_API_URL=https://api-test.example.com

# Test2
NEXT_PUBLIC_API_URL=https://api-stage.example.com

# Production
NEXT_PUBLIC_API_URL=https://api.example.com
```

## Troubleshooting

### Variable not available during build

**Symptom**: Build fails with "undefined" error

**Solution**:
1. Add variable in PaaS Portal > App Settings
2. Wait 2-3 minutes for changes to apply
3. Start new deployment

### Variable not available at runtime

**Symptom**: Application runs but variable is undefined

**Solution**:
1. Verify variable is set in App Settings for the correct environment
2. Restart application: Troubleshoot tab > Restart Web App
3. Check variable name spelling matches exactly

### NEXT_PUBLIC_ variable not working in browser

**Symptom**: Variable is undefined in browser console

**Common causes**:
1. Variable was added after build (must rebuild)
2. Typo in variable name
3. Missing `NEXT_PUBLIC_` prefix

**Solution**: These variables must be set BEFORE build. They're embedded during build time.

### Security warning: Secret exposed in browser

**Symptom**: Seeing secrets in browser DevTools

**Cause**: Used `NEXT_PUBLIC_` prefix on a secret variable

**Solution**:
1. Remove `NEXT_PUBLIC_` prefix
2. Move secret usage to server-side code
3. Redeploy with corrected configuration
4. Rotate the exposed secret immediately

## Next.js Specific Considerations

### App Router (Next.js 13+)

Server Components can access all environment variables:
```typescript
// app/page.tsx (Server Component)
export default async function Page() {
  const secret = process.env.API_SECRET; // ✓ Works
  // ...
}
```

Client Components can only access `NEXT_PUBLIC_` variables:
```typescript
'use client';
// app/component.tsx (Client Component)
export default function Component() {
  const apiUrl = process.env.NEXT_PUBLIC_API_URL; // ✓ Works
  const secret = process.env.API_SECRET; // ✗ Undefined
}
```

### Pages Router (Next.js 12 and earlier)

Server-side functions can access all variables:
```typescript
// pages/index.tsx
export async function getServerSideProps() {
  const secret = process.env.API_SECRET; // ✓ Works
  // ...
}
```

Client-side code needs `NEXT_PUBLIC_` prefix:
```typescript
// pages/index.tsx
export default function Page() {
  const apiUrl = process.env.NEXT_PUBLIC_API_URL; // ✓ Works
}
```

## Example Configuration

### Minimal Setup

```powershell
# Local deployment credentials
$env:OPTI_PROJECT_ID = "your-project-id"
$env:OPTI_CLIENT_KEY = "your-client-key"
$env:OPTI_CLIENT_SECRET = "your-client-secret"
```

PaaS Portal App Settings: (none required - Optimizely variables are automatic)

### Full Production Setup

Local deployment credentials (same as above)

PaaS Portal App Settings (Test1):
```
NEXT_PUBLIC_ANALYTICS_ID=GA-TEST-123
NEXT_PUBLIC_API_URL=https://api-test.example.com
SENDGRID_API_KEY=SG.test_xxxxx
ENABLE_DEBUG_MODE=true
```

PaaS Portal App Settings (Production):
```
NEXT_PUBLIC_ANALYTICS_ID=GA-PROD-456
NEXT_PUBLIC_API_URL=https://api.example.com
SENDGRID_API_KEY=SG.live_xxxxx
ENABLE_DEBUG_MODE=false
```

## Reference Links

- [Next.js Environment Variables](https://nextjs.org/docs/basic-features/environment-variables)
- [Azure App Service Environment Variables](https://learn.microsoft.com/en-us/azure/app-service/reference-app-settings)
- Optimizely PaaS Portal: https://paasportal.episerver.net/
