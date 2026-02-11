# Deployment Guide

Complete guide for deploying Next.js applications to Optimizely Frontend Hosting.

## Prerequisites

1. **Next.js Application**: A working Next.js project with proper configuration
2. **API Credentials**: Project ID, Client Key, and Client Secret from PaaS Portal
3. **PowerShell**: PowerShell 5.1 or later (Windows) or PowerShell Core (cross-platform)
4. **EpiCloud Module**: Will be installed automatically by deployment script

## Step 1: Obtain API Credentials

1. Log into your Optimizely CMS
2. Navigate to **Product Access** > **Developer Portal (frontend)** > **Details** tab
3. Confirm that **Opti ID Enabled** is selected
4. Go to **Admin Center** > **Users** > {your user} > **Add Product Access**
5. Ensure you have **Power User** access to the **Developer portal (front end)** product
6. Click **Developer Portal** from the top navigation or go to https://paasportal.episerver.net/
7. Navigate to the **API** tab
8. Click **Add API Credentials**
9. Copy the generated:
   - Project ID
   - Client Key
   - Client Secret
10. Select the environments you want to deploy to (Test1, Test2, Production)

## Step 2: Configure Environment Variables

Option A: Use the setup script (recommended):
```powershell
.\setup-env.ps1
```

Option B: Set manually for current session:
```powershell
$env:OPTI_PROJECT_ID = "<your_project_id>"
$env:OPTI_CLIENT_KEY = "<your_client_key>"
$env:OPTI_CLIENT_SECRET = "<your_client_secret>"
```

Option C: Set permanently (Windows):
```powershell
[System.Environment]::SetEnvironmentVariable("OPTI_PROJECT_ID", "<value>", "User")
[System.Environment]::SetEnvironmentVariable("OPTI_CLIENT_KEY", "<value>", "User")
[System.Environment]::SetEnvironmentVariable("OPTI_CLIENT_SECRET", "<value>", "User")
```

## Step 3: Prepare Your Next.js Project

### Required package.json Scripts

Your `package.json` must include these scripts:

```json
{
  "scripts": {
    "build": "next build",
    "start": "next start"
  }
}
```

The `build` script runs during deployment to generate static content and build the application.
The `start` script starts the Next.js server in production mode.

### Create .zipignore File

Create a `.zipignore` file in your project root to exclude unnecessary files:

```
# Build outputs (regenerated during deployment)
.next

# Dependencies (reinstalled during deployment)
node_modules

# Environment files (configured in PaaS Portal)
.env
.env.local
.env.*.local

# Version control
.git
.gitignore

# IDE files
.vscode
.idea
*.swp
*.swo
.DS_Store

# Testing
coverage
.nyc_output

# Misc
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
```

### Verify Project Structure

Ensure your project has this structure at minimum:
```
your-nextjs-app/
├── package.json          (required)
├── .zipignore           (recommended)
├── next.config.js       (if needed)
├── public/              (static assets)
├── src/ or app/         (your Next.js code)
└── ...other files
```

## Step 4: Deploy Using Automated Script

### Quick Deployment

From your project root:

```powershell
# Copy deploy.ps1 from the skill to your project
# Update $sourcePath in the script if needed
.\deploy.ps1
```

The script will:
1. Validate environment variables
2. Apply .zipignore exclusions
3. Create a timestamped deployment package
4. Upload to Azure BLOB storage
5. Trigger deployment to configured environment
6. Wait for deployment completion

### Customize Deployment

Edit `deploy.ps1` to change:

```powershell
# Target environment (line ~25)
$targetEnvironment = "Test1"  # Change to Test2, Production, etc.

# Source path (line ~28) - if script is not in project root
$sourcePath = "."  # Update to point to your Next.js app
```

## Step 5: Manual Deployment (Alternative)

If you prefer manual control or need to customize the process:

### Install EpiCloud Module

```powershell
Install-Module -Name EpiCloud -Scope CurrentUser -Force
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Import-Module EpiCloud
```

### Create Deployment Package

1. **Exclude files manually** or use a tool to apply .zipignore
2. **Create ZIP with specific naming**:
   - Format: `<name>.head.app.<version>.zip`
   - Example: `myapp.head.app.20250114.zip`
   - The `.head.app.` in the name is **critical** - without it, the system treats it as a .NET package
3. **Verify package contents**:
   - `package.json` must be at the root of the ZIP
   - No nested folders containing the application
   - Does NOT include `.next` or `node_modules`
   - DOES include `package-lock.json` or `yarn.lock`

### Upload and Deploy

```powershell
# Set configuration
$projectId = $env:OPTI_PROJECT_ID
$clientKey = $env:OPTI_CLIENT_KEY
$clientSecret = $env:OPTI_CLIENT_SECRET
$targetEnvironment = "Test1"
$packagePath = ".\myapp.head.app.20250114.zip"

# Connect to Optimizely Cloud
Connect-EpiCloud -ProjectId $projectId -ClientKey $clientKey -ClientSecret $clientSecret

# Get upload location
$sasUrl = Get-EpiDeploymentPackageLocation

# Upload package
Add-EpiDeploymentPackage -SasUrl $sasUrl -Path $packagePath

# Start deployment
Start-EpiDeployment `
    -DeploymentPackage "myapp.head.app.20250114.zip" `
    -TargetEnvironment $targetEnvironment `
    -DirectDeploy `
    -Wait `
    -Verbose
```

## Step 6: Monitor Deployment

### Check Status via PowerShell

```powershell
# View all deployments
Get-EpiDeployment

# View specific deployment
Get-EpiDeployment -Id <deployment-id>

# View as JSON for detailed information
Get-EpiDeployment -Id <deployment-id> | ConvertTo-Json
```

### Check Status in PaaS Portal

1. Navigate to https://paasportal.episerver.net/
2. Select your frontend project
3. Go to the **Deployment** tab
4. View **Recent Deployments** list
5. Click on a deployment to see detailed logs
6. Check for success or error messages

## Step 7: Post-Deployment Configuration

### Configure Visual Builder

After first deployment:

1. Go to **CMS > Settings > Import Data** to import content model
2. Go to **CMS > Settings > Applications** to create an application
3. Deploy your frontend (you just did this!)
4. Go to **Settings > Applications > Select your app > Hostnames**
5. Click **Add hostname** and enter the hostname from PaaS Portal
6. Go to **Settings > Scheduled jobs** to reindex content in Optimizely Graph

### Set Application Settings

In the PaaS Portal, **App Settings** tab:
1. Add any custom environment variables your app needs
2. These are available during build and runtime
3. Examples: API keys, feature flags, custom configuration

## Deployment Options

### DirectDeploy

For faster deployments to non-production environments:

```powershell
Start-EpiDeployment ... -DirectDeploy
```

Deploys directly to the Web App without slot swap. Available for:
- Test1
- Test2
- Integration (PaaS)
- Development (PaaS)

### Wait for Completion

```powershell
Start-EpiDeployment ... -Wait
```

Blocks until deployment completes. Useful for CI/CD pipelines.

### Verbose Logging

```powershell
Start-EpiDeployment ... -Verbose
```

Shows detailed progress information during deployment.

## Target Environment Names

### SaaS Frontend Hosting (SaaS CMS)
- `Test1`
- `Test2`
- `Production`

### PaaS Hosting (CMS 12)
- `Integration`
- `Preproduction`
- `Production`

## Package Versioning

Best practices for package versions:

```powershell
# Timestamp-based (recommended for automation)
myapp.head.app.20250114-153045.zip

# Semantic versioning
myapp.head.app.1.0.0.zip
myapp.head.app.1.0.1.zip
myapp.head.app.1.1.0.zip

# Build number
myapp.head.app.build-123.zip
```

**Important**: Cannot upload a package with the same name unless the content is identical (matching checksum).

## Next Steps

- See `troubleshooting.md` for common issues and solutions
- See `environment-variables.md` for detailed configuration options
- Configure monitoring and logging in PaaS Portal
- Set up CI/CD pipeline for automated deployments
