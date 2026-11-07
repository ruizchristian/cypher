# Builds a release APK in one step: format check, analyze, test, guard, build, release-permission
# audit, then copy it to dist\ with a readable name. Usage (from anywhere):
#   .\scripts\build-apk.ps1
#
# Mirrors .github/workflows/android.yml, so a local build and a CI build of the same commit are
# interchangeable: same checks, same signing key, same build-number scheme.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $env:Path += ';C:\src\flutter\bin'
}

function Step([string]$name, [scriptblock]$action) {
  Write-Host "`n==> $name" -ForegroundColor Cyan
  # Windows PowerShell turns any stderr line from a native tool (Gradle prints harmless warnings
  # there) into a terminating error under 'Stop'. Exit codes are the real signal, checked below.
  $ErrorActionPreference = 'Continue'
  & $action 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
}

if (-not (Test-Path 'android\key.properties')) {
  Write-Warning 'android\key.properties not found - this APK will be debug-signed and cannot update a properly signed install. See docs\release.md.'
}

# Build number from the UTC time (yyMMddHH), so every build - local or CI - is newer than the
# last and installs as an update instead of being refused as a downgrade.
$buildNumber = (Get-Date).ToUniversalTime().ToString('yyMMddHH')
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value)

Step 'Get dependencies' { flutter pub get }
Step 'Format check' { dart format --output=none --set-exit-if-changed lib test integration_test }
Step 'Analyze' { flutter analyze }
Step 'Test' { flutter test }
Step 'Guard (source)' { dart .claude/skills/verify/scripts/guard.dart }
Step 'Build release APK' { flutter build apk --release --build-number $buildNumber }
Step 'Guard (release permissions)' { dart .claude/skills/verify/scripts/guard.dart }

New-Item -ItemType Directory -Force dist | Out-Null
$out = "dist\CypherAuth-$version-$buildNumber.apk"
Copy-Item build\app\outputs\flutter-apk\app-release.apk $out -Force

$size = '{0:N1} MB' -f ((Get-Item $out).Length / 1MB)
Write-Host "`nDone: $out ($size)" -ForegroundColor Green
