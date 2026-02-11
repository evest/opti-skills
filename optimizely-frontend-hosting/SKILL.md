---
name: optimizely-frontend-hosting
description: Configure and deploy Next.js applications to Optimizely Frontend Hosting for CMS (SaaS). Use this skill when the user needs to (1) Set up frontend hosting configuration, (2) Deploy a Next.js app to Optimizely Frontend Hosting, (3) Manage environment variables for frontend hosting, (4) Create deployment scripts, or (5) Troubleshoot frontend hosting deployments. This skill is specifically for Optimizely SaaS CMS, not CMS 12 (PaaS).
---

# Optimizely Frontend Hosting

Deploy and manage Next.js applications on Optimizely Frontend Hosting for CMS (SaaS).

## Overview

Optimizely Frontend Hosting is a cloud-based solution for deploying headless Next.js applications with an Optimizely CMS (SaaS) backend. It provides managed environments (Test1, Test2, Production) with built-in CDN and WAF powered by Cloudflare.

**Key characteristics:**
- Next.js support only (SSG and SSR, ISR not yet supported)
- Managed environments integrated with CMS (SaaS)
- Automatic CDN and WAF configuration
- Static site hosting with Azure infrastructure

## Workflow Decision Tree

**User says "Set up frontend hosting":**
1. Check if environment variables exist in project
2. If missing, read `references/environment-variables.md` for guidance
3. Create `.env` file with required variables
4. Create or update `.zipignore` from `assets/.zipignore.template`
5. Verify `package.json` has required scripts (see `assets/package.json.template`)
6. Guide user on obtaining API credentials from PaaS Portal

**User says "Deploy to frontend hosting":**
1. Read `references/deployment-guide.md` for detailed process
2. Use `scripts/deploy.ps1` for automated deployment
3. Or guide through manual PowerShell deployment steps
4. Monitor deployment status

**User says "Configure deployment settings":**
1. Check current environment variables
2. Read `references/environment-variables.md` for details
3. Use `scripts/setup-env.ps1` to configure variables

**User encounters deployment errors:**
1. Read `references/troubleshooting.md` for common issues
2. Check deployment logs
3. Verify package naming and structure

## Environment Setup

### Required Environment Variables

Three environment variables must be set before deployment:

```powershell
$env:OPTI_PROJECT_ID = "<your_project_id>"
$env:OPTI_CLIENT_KEY = "<your_client_key>"
$env:OPTI_CLIENT_SECRET = "<your_client_secret>"
```

These are obtained from **PaaS Portal > API tab** for your frontend project.

For permanent setup, use `scripts/setup-env.ps1` or add to system environment variables.

### Project Configuration

Ensure the Next.js project has:

1. **package.json** with required scripts:
```json
{
  "scripts": {
    "build": "next build",
    "start": "next start"
  }
}
```

2. **.zipignore** file to exclude:
   - `.next`
   - `node_modules`
   - `.env`
   - `.git`
   - `.DS_Store`
   - `.vscode`

See `assets/.zipignore.template` for complete example.

## Deployment Process

### Quick Deployment (Automated)

For automated deployment, use the provided script:

```powershell
# From project root
.\deploy.ps1
```

The script (located in `scripts/deploy.ps1`):
- Validates environment variables
- Creates deployment package with .zipignore support
- Uploads to Azure
- Triggers deployment to configured environment

### Manual Deployment Steps

For detailed manual deployment process, read `references/deployment-guide.md`. Summary:

1. **Install EpiCloud module**:
```powershell
Install-Module -Name EpiCloud -Scope CurrentUser -Force
Import-Module EpiCloud
```

2. **Create deployment package**:
   - Package name format: `<n>.head.app.<version>.zip`
   - Example: `myapp.head.app.20250610.zip`
   - Must include `package.json` at root
   - Exclude `.next` and `node_modules`

3. **Upload and deploy**:
```powershell
Connect-EpiCloud -ProjectId $projectId -ClientKey $clientKey -ClientSecret $clientSecret
$sasUrl = Get-EpiDeploymentPackageLocation
Add-EpiDeploymentPackage -SasUrl $sasUrl -Path .\myapp.head.app.20250610.zip
Start-EpiDeployment -DeploymentPackage "myapp.head.app.20250610.zip" -TargetEnvironment Test1 -DirectDeploy -Wait -Verbose
```

### Target Environments

For **SaaS Frontend Hosting**, use:
- `Test1`
- `Test2`
- `Production`

For **PaaS hosting** (CMS 12), use:
- `Integration`
- `Preproduction`
- `Production`

## Runtime Environment Variables

The following variables are automatically available during build and runtime:

- `OPTIMIZELY_CMS_URL` - CMS backend URL
- `OPTIMIZELY_GRAPH_GATEWAY` - Optimizely Graph endpoint
- `OPTIMIZELY_GRAPH_SECRET` - Graph authentication secret
- `OPTIMIZELY_GRAPH_SINGLE_KEY` - Graph single key
- `OPTIMIZELY_GRAPH_APP_KEY` - Graph app key

**Important!** the `OPTIMIZELY_GRAPH_GATEWAY` environment variable in the Optimizely Frontend Hosting runtime does not have a path to the Graph API, only the full hostname. Typically this is: `https://cg.optimizely.com` while the Optimizely Content JS SDK needs the full path to the Graph like ``

Here is an example library function to use when getting the full path:
```typescript
const DEFAULT_GRAPH_PATH = "/content/v2";

/**
 * Returns the Optimizely Graph gateway URL with the full path.
 *
 * In production (Frontend Hosting), the env var may be set to just the base URL:
 *   "https://cg.optimizely.com"
 *
 * Locally it includes the full path:
 *   "https://cg.optimizely.com/content/v2"
 *
 * This function ensures the full path is always present.
 * The path can be configured via OPTIMIZELY_GRAPH_PATH env var.
 */
export function getGraphGatewayUrl(): string {
  const gateway = process.env.OPTIMIZELY_GRAPH_GATEWAY;
  const graphPath = process.env.OPTIMIZELY_GRAPH_PATH || DEFAULT_GRAPH_PATH;

  if (!gateway) {
    throw new Error("OPTIMIZELY_GRAPH_GATEWAY environment variable is not set");
  }

  // If the gateway already ends with the path, return as-is
  if (gateway.endsWith(graphPath)) {
    return gateway;
  }

  // Remove trailing slash if present, then append the path
  const baseUrl = gateway.replace(/\/+$/, "");
  return `${baseUrl}${graphPath}`;
}
```

It is being used like this:
```typescript
  const client = new GraphClient(process.env.OPTIMIZELY_GRAPH_SINGLE_KEY!, {
    graphUrl: getGraphGatewayUrl(),
  });
```

Additional app settings can be configured through the Management Portal UI.

## Common Tasks

### Check Current Configuration

```powershell
# View environment variables
echo $env:OPTI_PROJECT_ID
echo $env:OPTI_CLIENT_KEY
echo $env:OPTI_CLIENT_SECRET

# Check deployment status
Get-EpiDeployment
```

### Update Deployment Script Settings

Edit `scripts/deploy.ps1` to customize:
- `$sourcePath` - Path to Next.js app
- `$targetEnvironment` - Target environment name

### Troubleshoot Deployment Issues

For troubleshooting, read `references/troubleshooting.md` which covers:
- Missing environment variables during build
- Invalid ZIP package structure
- Incorrect naming conventions
- Build failures
- File exclusion issues

## Additional Resources

- **scripts/deploy.ps1**: Complete automated deployment script
- **scripts/setup-env.ps1**: Environment variable configuration helper
- **references/deployment-guide.md**: Detailed deployment walkthrough
- **references/troubleshooting.md**: Common issues and solutions
- **references/environment-variables.md**: Environment configuration details
- **assets/.zipignore.template**: Template for file exclusions
- **assets/package.json.template**: Example Next.js package.json
