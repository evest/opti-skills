# Troubleshooting Guide

Common issues and solutions when deploying to Optimizely Frontend Hosting.

## Critical Mistakes to Avoid

### 1. Missing Environment Variables

**Problem**: Deployment starts but build fails immediately because environment variables are not set.

**Why it happens**: The deployment process triggers a production build (`npm run build` or `yarn build`) immediately. If required environment variables are missing, the build fails and the environment can remain locked.

**Solution**: Always set ALL required environment variables in the PaaS Portal BEFORE starting deployment.

**How to fix**:
1. Go to PaaS Portal > App Settings tab
2. Add all required environment variables
3. Wait for settings to apply (may take a few minutes)
4. Then start deployment

**Variables to set**:
- `OPTIMIZELY_CMS_URL` - Set via PaaS Portal
- `OPTIMIZELY_GRAPH_GATEWAY` - Set via PaaS Portal
- `OPTIMIZELY_GRAPH_SECRET` - Set via PaaS Portal
- `OPTIMIZELY_GRAPH_SINGLE_KEY` - Set via PaaS Portal
- `OPTIMIZELY_GRAPH_APP_KEY` - Set via PaaS Portal
- Any custom variables your app needs (API keys, feature flags, etc.)

### 2. Invalid ZIP Structure

**Problem**: Package is rejected or build fails because files are not at the root level.

**Why it happens**: Using Windows "Send to ZIP" or similar tools wraps files in an extra folder.

**Solution**: Create ZIP properly with `package.json` at root level.

**Example of CORRECT structure**:
```
myapp.head.app.1.0.0.zip
├── package.json          ← At root level
├── package-lock.json
├── next.config.js
├── public/
├── src/
└── ...
```

**Example of INCORRECT structure**:
```
myapp.head.app.1.0.0.zip
└── myapp/                ← Extra folder
    ├── package.json      ← NOT at root
    ├── package-lock.json
    └── ...
```

**How to verify**: Extract the ZIP and check that `package.json` is immediately visible.

**How to create correct ZIP**:
- Use the provided `deploy.ps1` script (handles this automatically)
- Or use PowerShell: `Compress-Archive -Path .\* -DestinationPath package.zip`
- Or use 7-Zip: Select files (not folder), right-click > 7-Zip > Add to archive

### 3. Missing Files Due to Incorrect Patterns

**Problem**: Deployment succeeds but application doesn't work correctly. Files like `page.tsx` in route groups or dynamic routes are missing.

**Why it happens**: Automation scripts or ZIP tools may not handle special folder names correctly:
- Route groups: `(marketing)`, `(auth)`, `(shop)`
- Dynamic routes: `[slug]`, `[id]`, `[...catchAll]`

**Solution**: Verify ZIP contents before uploading.

**How to check**:
```powershell
# Extract and inspect
Expand-Archive -Path .\myapp.head.app.1.0.0.zip -DestinationPath .\temp-check
tree /F .\temp-check

# Look for:
# - All route group folders: (marketing), (auth), etc.
# - All dynamic route folders: [slug], [id], etc.
# - All page.tsx, layout.tsx, loading.tsx files
```

**Prevention**: Use the provided `deploy.ps1` script which handles all file types correctly.

### 4. Incorrect Package Naming

**Problem**: Package is treated as a .NET NuGet package instead of a frontend package.

**Why it happens**: Package name doesn't follow the required convention.

**Solution**: Always use `.head.app.` in the filename.

**Correct naming examples**:
```
myapp.head.app.1.0.0.zip          ✓
site.head.app.20250114.zip        ✓
frontend.head.app.build-123.zip   ✓
```

**Incorrect naming examples**:
```
myapp.1.0.0.zip                   ✗ (missing .head.app.)
myapp.head.1.0.0.zip              ✗ (typo: should be .head.app.)
myapp-head-app-1.0.0.zip          ✗ (using dashes instead of dots)
```

### 5. Including node_modules or .next

**Problem**: Deployment package is huge and takes very long to upload.

**Why it happens**: Including `node_modules` (dependencies) or `.next` (build output) in the package.

**Solution**: Exclude these directories - they are regenerated during deployment.

**Why they're excluded**:
- `node_modules`: Dependencies are installed during deployment via `npm install` or `yarn install`
- `.next`: Build output is generated during deployment via `npm run build` or `yarn build`

**How to exclude**:
1. Create `.zipignore` file (recommended - automated by `deploy.ps1`)
2. Or manually exclude when creating ZIP

**Typical .zipignore**:
```
.next
node_modules
.env
.git
```

**Before/After**:
- With node_modules: ~300-500 MB package ✗
- Without node_modules: ~5-20 MB package ✓

## Build Errors

### "Module not found" or "Cannot find package"

**Cause**: Missing dependency in `package.json` or `yarn.lock`/`package-lock.json` not included.

**Solution**:
1. Ensure `package-lock.json` (npm) or `yarn.lock` (yarn) is in your package
2. Verify all dependencies are listed in `package.json`
3. Run `npm install` or `yarn install` locally to regenerate lock file if needed

### "Environment variable ... is not defined"

**Cause**: Required environment variable not set in PaaS Portal before deployment.

**Solution**:
1. Stop current deployment if it's running
2. Go to PaaS Portal > App Settings
3. Add the missing environment variable
4. Wait a few minutes for settings to apply
5. Start new deployment

### "Build script not found"

**Cause**: Missing or incorrectly named build script in `package.json`.

**Solution**: Ensure `package.json` has:
```json
{
  "scripts": {
    "build": "next build",
    "start": "next start"
  }
}
```

### Build timeout

**Cause**: Build takes too long (>20 minutes).

**Solution**:
1. Optimize build process
2. Reduce bundle size
3. Check for infinite loops or hanging processes
4. Ensure no unnecessary heavy computations during build

## Deployment Errors

### "Authentication failed"

**Cause**: Invalid or expired credentials.

**Solution**:
```powershell
# Verify environment variables
echo $env:OPTI_PROJECT_ID
echo $env:OPTI_CLIENT_KEY
echo $env:OPTI_CLIENT_SECRET

# If wrong, re-run setup
.\setup-env.ps1
```

### "Package already exists"

**Cause**: Trying to upload a package with the same name but different content.

**Solution**: Use a different version number or timestamp in the package name.

```powershell
# Auto-generate unique name with timestamp
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$zipName = "myapp.head.app.$timestamp.zip"
```

### "Target environment not found"

**Cause**: Incorrect environment name or credentials don't have access.

**Solution**:
1. Verify environment name matches exactly (Test1, Test2, Production)
2. Check API credentials have access to this environment in PaaS Portal
3. Re-generate API credentials with correct environment access if needed

### "Deployment failed" (generic)

**Cause**: Various reasons - need to check logs.

**Solution**:
1. Go to PaaS Portal > Deployment tab
2. Click on the failed deployment
3. View detailed logs
4. Look for specific error messages
5. Check troubleshooting sections above based on error

## Runtime Issues

### Application doesn't start

**Check**:
1. PaaS Portal > Troubleshoot tab > Application Logs
2. Look for startup errors
3. Verify `start` script in `package.json`: `"start": "next start"`

### Environment variables not available at runtime

**Check**:
1. PaaS Portal > App Settings tab
2. Verify variables are set
3. Restart application: Troubleshoot tab > Restart Web App

### Visual Builder not showing content

**Cause**: Application not properly configured in CMS or hostname mapping missing.

**Solution**:
1. CMS > Settings > Applications
2. Create/select your application
3. Go to Hostnames section
4. Add hostname from PaaS Portal (e.g., `test1-myapp.cms.optimizely.com`)
5. Settings > Scheduled jobs > Reindex content

### CDN not serving latest content

**Solution**:
1. PaaS Portal > Troubleshoot tab
2. Click "Purge Cache"
3. Wait a few minutes for cache to clear

## Getting Help

### Enable verbose logging

During deployment:
```powershell
Start-EpiDeployment ... -Verbose
```

### Check deployment details

```powershell
# List all deployments
Get-EpiDeployment

# Get specific deployment
$deployment = Get-EpiDeployment -Id <deployment-id>

# View as JSON
$deployment | ConvertTo-Json -Depth 10
```

### View application logs

1. PaaS Portal > Troubleshoot tab
2. Click "Open Log Stream Window"
3. Watch real-time logs from your application

### Export logs

1. PaaS Portal > Troubleshoot tab
2. Application Logs section
3. Generate download link
4. Download and analyze logs locally

## Prevention Checklist

Before each deployment, verify:

- [ ] Environment variables set in PaaS Portal
- [ ] `.zipignore` file exists and is correct
- [ ] `package.json` has `build` and `start` scripts
- [ ] Package name follows `<n>.head.app.<version>.zip` format
- [ ] `package-lock.json` or `yarn.lock` is included
- [ ] `.next` and `node_modules` are excluded
- [ ] Test locally that `npm run build` or `yarn build` works
- [ ] All route groups and dynamic routes are included

## Common Questions

**Q: How long does deployment take?**
A: Typically 5-10 minutes. Depends on:
- Package upload size
- Number of dependencies to install
- Build complexity
- Environment load

**Q: Can I deploy to multiple environments at once?**
A: No, deploy to one environment at a time. Wait for completion before deploying to next environment.

**Q: What happens if deployment fails midway?**
A: The environment remains in its previous state. No partial updates. Fix the issue and deploy again.

**Q: Can I rollback a deployment?**
A: Yes, deploy a previous package version. Keep track of working package versions.

**Q: How do I update just environment variables without redeploying?**
A: Update in PaaS Portal > App Settings. Then restart the application.

**Q: The environment is locked, what do I do?**
A: Usually means a deployment is in progress. Wait for it to complete or fail. If stuck, contact Optimizely Support.

## Contact Support

If issues persist:
1. Gather deployment logs and error messages
2. Note the deployment ID
3. Contact Optimizely Support via PaaS Portal
4. Provide: project ID, environment name, deployment ID, error details
