# run_app.ps1 — Build & deploy Tesseract Windows using credentials from .env
#
# Usage:
#   .\run_app.ps1          # hot-reload debug run
#   .\run_app.ps1 -Release # build release windows app
#

param (
    [switch]$Release
)

$ErrorActionPreference = "Stop"

$EnvFile = Join-Path $PSScriptRoot ".env"
if (-Not (Test-Path $EnvFile)) {
    Write-Host "X  .env file not found at $EnvFile" -ForegroundColor Red
    Write-Host "   Please copy .env.example to .env and configure TELEGRAM_API_ID and hash."
    exit 1
}

# Parse .env
$envVars = @{}
Get-Content $EnvFile | Where-Object { $_ -match '=' -and $_ -notmatch '^\s*#' } | ForEach-Object {
    $parts = $_.Split('=', 2)
    $envVars[$parts[0].Trim()] = $parts[1].Trim()
}

$apiId = $envVars["TELEGRAM_API_ID"]
$apiHash = $envVars["TELEGRAM_API_HASH"]

if ([string]::IsNullOrWhiteSpace($apiId) -or [string]::IsNullOrWhiteSpace($apiHash)) {
    Write-Host "X  TELEGRAM_API_ID or TELEGRAM_API_HASH missing in .env" -ForegroundColor Red
    exit 1
}

$Defines = "--dart-define=TELEGRAM_API_ID=$apiId", "--dart-define=TELEGRAM_API_HASH=$apiHash"

if ($Release) {
    Write-Host "O  Building release Windows app..." -ForegroundColor Cyan
    $targetDir = Join-Path $PSScriptRoot "build\windows\x64\runner\Release"
} else {
    Write-Host "O  Running debug build for Windows (hot-reload enabled)..." -ForegroundColor Cyan
    $targetDir = Join-Path $PSScriptRoot "build\windows\x64\runner\Debug"
}

# Setup tdjson.dll
Write-Host "O  Checking for tdjson.dll..." -ForegroundColor Cyan
$NodeModulesDir = Join-Path $PSScriptRoot "node_modules\@prebuilt-tdlib\win32-x64"
if (-Not (Test-Path (Join-Path $NodeModulesDir "tdjson.dll"))) {
    Write-Host "   Installing @prebuilt-tdlib/win32-x64 via npm..." -ForegroundColor Cyan
    if (-Not (Test-Path (Join-Path $PSScriptRoot "package.json"))) {
        npm init -y | Out-Null
    }
    npm install @prebuilt-tdlib/win32-x64@0.1008050.0 --force
}

if (-Not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
}

Copy-Item (Join-Path $NodeModulesDir "tdjson.dll") -Destination $targetDir -Force
Write-Host "   Copied tdjson.dll to $targetDir" -ForegroundColor Green

if ($Release) {
    flutter build windows --release --dart-define="TELEGRAM_API_ID=$apiId" --dart-define="TELEGRAM_API_HASH=$apiHash"
    Write-Host "V  Build complete! Executable is at $targetDir\tesseract.exe" -ForegroundColor Green
} else {
    flutter run -d windows --dart-define="TELEGRAM_API_ID=$apiId" --dart-define="TELEGRAM_API_HASH=$apiHash"
}
