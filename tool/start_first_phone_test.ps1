param(
  [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'

if ($Port -lt 1 -or $Port -gt 65535) {
  throw 'Port must be between 1 and 65535.'
}
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
  throw 'LOCALAPPDATA is required for the isolated synthetic test directory.'
}

$projectDirectory = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $PSScriptRoot 'local_sync_server.dart'
if (-not (Test-Path -LiteralPath $serverScript)) {
  throw "Server source not found: $serverScript"
}
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
  throw 'Dart is not installed or is not on PATH. Install the Dart SDK before this test.'
}

function New-TestKey {
  $bytes = New-Object byte[] 24
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($bytes)
  } finally {
    $rng.Dispose()
  }
  return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

$testRoot = Join-Path $env:LOCALAPPDATA 'NutritionStudy\synthetic-phone-tests'
$testDirectory = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null

$collectorKey = New-TestKey
$adminKey = New-TestKey
$env:LOCAL_SYNC_COLLECTOR_KEYS = "C001:$collectorKey"
$env:LOCAL_SYNC_ADMIN_KEY = $adminKey
Remove-Item Env:LOCAL_SYNC_KEY -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'SYNTHETIC PHONE TEST ONLY — never enter real participant details.'
Write-Host "Data directory: $testDirectory\.local_data"
Write-Host "Collector number: 1"
Write-Host "Collector access key: $collectorKey"
Write-Host "Administrator access key: $adminKey"
Write-Host "Phone server URL: http://<this-PC-LAN-IP>:$Port"
Write-Host 'Keep this window open while testing. Press Ctrl+C to stop the server.'
Write-Host 'The isolated synthetic records are retained after the server stops.'
Write-Host ''

Push-Location $testDirectory
try {
  & dart $serverScript --host=0.0.0.0 --port=$Port
  if ($LASTEXITCODE -ne 0) {
    throw "Study server exited with code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}
