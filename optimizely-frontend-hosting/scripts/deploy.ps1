# Optimizely Frontend Hosting Deployment Script
#
# This script automates the deployment of Next.js applications to Optimizely Frontend Hosting
# Supports .zipignore for excluding files from the deployment package

# Load .env file if it exists
$envFile = Join-Path (Get-Location) ".env"
if (Test-Path $envFile) {
    Write-Host "Loading environment variables from .env..." -ForegroundColor Cyan
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*?)\s*=\s*(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            # Remove surrounding quotes if present
            if ($value -match '^[''"](.*)[''""]$') {
                $value = $matches[1]
            }
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# Check required environment variables
if (-not $env:OPTI_PROJECT_ID -or -not $env:OPTI_CLIENT_KEY -or -not $env:OPTI_CLIENT_SECRET) {
    Write-Host "Missing one or more required environment variables: OPTI_PROJECT_ID, OPTI_CLIENT_KEY, OPTI_CLIENT_SECRET" -ForegroundColor Red
    Write-Host "Please set these in your .env file or as environment variables." -ForegroundColor Yellow
    Write-Host "You can find these values in the PaaS Portal > API tab for your frontend project." -ForegroundColor Yellow
    exit 1
}

# Install and import EpiCloud module
Write-Host "Checking EpiCloud module..." -ForegroundColor Cyan
Install-Module -Name EpiCloud -Scope CurrentUser -Force -ErrorAction SilentlyContinue

# Set execution policy only if needed (suppress errors if overridden by group policy)
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -eq "Restricted" -or $currentPolicy -eq "Undefined") {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
}

Import-Module EpiCloud

# Settings
$projectId = $env:OPTI_PROJECT_ID
$clientKey = $env:OPTI_CLIENT_KEY
$clientSecret = $env:OPTI_CLIENT_SECRET
$targetEnvironment = if ($env:OPTI_TARGET_ENV) { $env:OPTI_TARGET_ENV } else { "Test1" }

# Path to the root of your Next.js app (resolve to full path for reliable path calculations)
$sourcePath = (Resolve-Path ".").Path

# Generate unique zip filename
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$projectName = Split-Path -Leaf $sourcePath
$zipName = "$projectName.head.app.$timestamp.zip"
$zipPath = ".\$zipName"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Optimizely Frontend Hosting Deploy" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Project: $projectName" -ForegroundColor White
Write-Host "Target Environment: $targetEnvironment" -ForegroundColor White
Write-Host "Package: $zipName" -ForegroundColor White
Write-Host ""

# Clean up old deployment packages
$oldPackages = Get-ChildItem -Path $sourcePath -Filter "$projectName.head.app.*.zip" -File
if ($oldPackages.Count -gt 0) {
    Write-Host "Cleaning up $($oldPackages.Count) old deployment package(s)..." -ForegroundColor Yellow
    $oldPackages | Remove-Item -Force
}

# Load .zipignore file if it exists
$zipIgnorePath = Join-Path $sourcePath ".zipignore"
$excludeRoot = @()
if (Test-Path $zipIgnorePath) {
    Write-Host "Loading .zipignore..." -ForegroundColor Cyan
    $excludeRoot = Get-Content $zipIgnorePath | Where-Object { $_ -and $_ -notmatch "^#" }
    Write-Host "Found $($excludeRoot.Count) exclusion patterns" -ForegroundColor Cyan
}
else {
    Write-Host "No .zipignore file found - including all files" -ForegroundColor Yellow
}

$rootExcludes = $excludeRoot | ForEach-Object { Join-Path $sourcePath $_ }

# Collect files excluding those in .zipignore
Write-Host "Collecting files..." -ForegroundColor Cyan
$includeFiles = Get-ChildItem -Path $sourcePath -Recurse -File | Where-Object {
    $filePath = $_.FullName
    foreach ($ex in $rootExcludes) {
        # Use platform-agnostic separator for pattern matching
        $exPattern = $ex -replace '\\', '/'
        $filePathNormalized = $filePath -replace '\\', '/'
        if ($filePathNormalized -like "$exPattern/*" -or $filePathNormalized -eq $exPattern) {
            return $false
        }
    }
    return $true
}

if ($includeFiles.Count -eq 0) {
    Write-Host "ERROR: No files to archive after applying .zipignore filters." -ForegroundColor Red
    exit 1
}

Write-Host "Found $($includeFiles.Count) files to include" -ForegroundColor Green

# Prepare temporary folder for zipping
$tempPath = Join-Path $env:TEMP "nextjs-build-zip-$timestamp"
if (Test-Path $tempPath) { Remove-Item -Recurse -Force $tempPath }
New-Item -ItemType Directory -Path $tempPath | Out-Null

Write-Host "Preparing archive..." -ForegroundColor Cyan
foreach ($file in $includeFiles) {
    $relativePath = $file.FullName.Substring($sourcePath.Length).TrimStart('\')
    $destPath = Join-Path $tempPath $relativePath
    $destDir = Split-Path -Path $destPath -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
}

# Create the ZIP archive
Write-Host "Creating ZIP archive..." -ForegroundColor Cyan
Compress-Archive -Path "$tempPath\*" -DestinationPath $zipPath
if (-not (Test-Path $zipPath)) {
    Write-Host "ERROR: Failed to create ZIP file." -ForegroundColor Red
    exit 1
}
Remove-Item -Recurse -Force $tempPath

$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "Package created: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Green
Write-Host ""

# Authenticate and deploy
Write-Host "Connecting to Optimizely Cloud..." -ForegroundColor Cyan
Connect-EpiCloud -ProjectId $projectId -ClientKey $clientKey -ClientSecret $clientSecret

Write-Host "Getting SAS URL..." -ForegroundColor Cyan
$sasUrl = Get-EpiDeploymentPackageLocation

Write-Host "Uploading deployment package..." -ForegroundColor Cyan
Add-EpiDeploymentPackage -SasUrl $sasUrl -Path $zipPath

Write-Host ""
Write-Host "Starting deployment to $targetEnvironment..." -ForegroundColor Cyan
Write-Host "This may take several minutes. Please wait..." -ForegroundColor Yellow
Write-Host ""

Start-EpiDeployment `
    -DeploymentPackage $zipName `
    -TargetEnvironment $targetEnvironment `
    -DirectDeploy `
    -Wait `
    -Verbose

Write-Host ""
Write-Host "==================================" -ForegroundColor Green
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host "Your Next.js application has been deployed to $targetEnvironment" -ForegroundColor White
Write-Host ""
