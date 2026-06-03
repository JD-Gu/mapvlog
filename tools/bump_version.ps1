param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][int]$Build
)
# PinFlick version bump helper.
# Usage: tools\bump_version.ps1 -Version 1.35.0 -Build 47
# Syncs pubspec.yaml + lib/utils/constants.dart + web/version.json.

$root = Split-Path -Parent $PSScriptRoot

# 1. pubspec.yaml
$pubspec = Join-Path $root 'pubspec.yaml'
(Get-Content $pubspec -Raw -Encoding UTF8) `
    -replace 'version:\s+[\d.]+\+\d+', "version: $Version+$Build" `
    | Set-Content $pubspec -NoNewline -Encoding UTF8
Write-Host "  pubspec.yaml         version: $Version+$Build" -ForegroundColor Green

# 2. constants.dart
$constants = Join-Path $root 'lib\utils\constants.dart'
$c = Get-Content $constants -Raw -Encoding UTF8
$c = $c -replace "const String kAppVersion = '[\d.]+';", "const String kAppVersion = '$Version';"
$c = $c -replace "const String kAppBuildNumber = '\d+';", "const String kAppBuildNumber = '$Build';"
Set-Content -Path $constants -Value $c -NoNewline -Encoding UTF8
Write-Host "  constants.dart       kAppVersion / kAppBuildNumber updated" -ForegroundColor Green

# 3. web/version.json
$verJson = Join-Path $root 'web\version.json'
$json = '{' + "`n" + '  "version": "' + $Version + '",' + "`n" + '  "build": "' + $Build + '"' + "`n" + '}'
Set-Content -Path $verJson -Value $json -NoNewline -Encoding UTF8
Write-Host "  web/version.json     web auto-update poll target" -ForegroundColor Green

Write-Host ""
Write-Host "Version $Version+$Build synced. Next steps:" -ForegroundColor Cyan
Write-Host "  flutter build web --release" -ForegroundColor Yellow
Write-Host "  flutter build apk --release" -ForegroundColor Yellow
Write-Host "  firebase deploy --only hosting" -ForegroundColor Yellow
