param(
  [string]$FlutterCommand = "flutter",
  [string]$BuildName = "1.0.0",
  [int]$BuildNumber = 1,
  [string]$LocalApiBaseUrl = "",
  [string]$CollectorApiKey = "",
  [string]$CollectorId = "",
  [int]$CollectorNumber = 0,
  [switch]$SigningBackupConfirmed
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot
$keyProperties = Join-Path $projectDirectory "android/key.properties"
$keystore = Join-Path $projectDirectory "android/app/study-release.jks"
$distributionRoot = Join-Path $projectDirectory "dist/android"

if (-not $SigningBackupConfirmed) {
  throw "Before building a signed release, copy the keystore AND key.properties to a separate secure location, verify they can be read, then pass -SigningBackupConfirmed."
}

if (-not (Test-Path -LiteralPath $keyProperties)) {
  throw "Missing android/key.properties. Create and back up the release signing key before packaging."
}
if (-not (Test-Path -LiteralPath $keystore)) {
  throw "Missing android/app/study-release.jks. Updates require the same signing key."
}
if ($BuildNumber -lt 1) {
  throw "BuildNumber must be at least 1."
}
if ($BuildName -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
  throw "BuildName must be a numeric version such as 1.0.0."
}
$hasUrl = -not [string]::IsNullOrWhiteSpace($LocalApiBaseUrl)
$hasKey = -not [string]::IsNullOrWhiteSpace($CollectorApiKey)
if ($hasUrl -ne $hasKey) {
  throw "LocalApiBaseUrl and CollectorApiKey must be supplied together."
}
if ($hasKey -and $CollectorApiKey.Length -lt 16) {
  throw "CollectorApiKey must be at least 16 characters."
}
if ($hasUrl) {
  $apiUri = $null
  if (-not [Uri]::TryCreate($LocalApiBaseUrl, [UriKind]::Absolute, [ref]$apiUri) -or
      $apiUri.Scheme -notin @('http', 'https') -or
      -not [string]::IsNullOrEmpty($apiUri.UserInfo) -or
      -not [string]::IsNullOrEmpty($apiUri.Query) -or
      -not [string]::IsNullOrEmpty($apiUri.Fragment)) {
    throw "LocalApiBaseUrl must be an absolute HTTP(S) URL without credentials, query, or fragment."
  }
}

if ($CollectorNumber -lt 0 -or $CollectorNumber -gt 99) {
  throw "CollectorNumber must be between 0 and 99."
}
$CollectorId = $CollectorId.Trim().ToUpperInvariant()
if ($CollectorNumber -gt 0) {
  $numberId = "C{0:D3}" -f $CollectorNumber
  if ($CollectorId -and $CollectorId -ne $numberId) {
    throw "CollectorId and CollectorNumber must identify the same collector."
  }
  $CollectorId = $numberId
}
if ($CollectorId -and $CollectorId -notmatch '^C[0-9]{3}$') {
  throw "CollectorId must use the C001 format."
}
if ($CollectorId -and ([int]$CollectorId.Substring(1) -lt 1 -or [int]$CollectorId.Substring(1) -gt 99)) {
  throw "CollectorId must be between C001 and C099."
}
if ($hasUrl -and -not $CollectorId) {
  throw "A LAN release requires CollectorId or CollectorNumber."
}

$distributionDirectory = Join-Path $distributionRoot $(if ($CollectorId) { $CollectorId } else { 'unprovisioned' })
$artifactBase = "study-collector-$BuildName+$BuildNumber"
$apkDestination = Join-Path $distributionDirectory "$artifactBase.apk"
$bundleDestination = Join-Path $distributionDirectory "$artifactBase.aab"
$checksumDestination = Join-Path $distributionDirectory "$artifactBase.sha256"
foreach ($destination in @($apkDestination, $bundleDestination, $checksumDestination)) {
  if (Test-Path -LiteralPath $destination) {
    throw "Release artifact already exists: $destination. Increase BuildNumber; existing packages are never replaced."
  }
}
if (Test-Path -LiteralPath $distributionDirectory) {
  foreach ($existing in @(Get-ChildItem -LiteralPath $distributionDirectory -Filter 'study-collector-*.apk' -File)) {
    if ($existing.Name -match '^study-collector-[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)\.apk$' -and
        [int]$Matches[1] -ge $BuildNumber) {
      throw "BuildNumber must exceed the previous release in $distributionDirectory ($($existing.Name))."
    }
  }
}

$localDefines = @()
if ($hasUrl) {
  $localDefines += @(
    "--dart-define=LOCAL_API_BASE_URL=$LocalApiBaseUrl",
    "--dart-define=LOCAL_API_KEY=$CollectorApiKey"
  )
}
if (-not [string]::IsNullOrWhiteSpace($CollectorId)) {
  $localDefines += "--dart-define=LOCAL_COLLECTOR_ID=$CollectorId"
}

Push-Location $projectDirectory
try {
  & $FlutterCommand build apk --release --target lib/main.dart --build-name $BuildName --build-number $BuildNumber @localDefines
  if ($LASTEXITCODE -ne 0) { throw "Release APK build failed." }

  & $FlutterCommand build appbundle --release --target lib/main.dart --build-name $BuildName --build-number $BuildNumber @localDefines
  if ($LASTEXITCODE -ne 0) { throw "Release App Bundle build failed." }

  New-Item -ItemType Directory -Force -Path $distributionDirectory | Out-Null
  $apkSource = Join-Path $projectDirectory 'build/app/outputs/flutter-apk/app-release.apk'
  $bundleSource = Join-Path $projectDirectory 'build/app/outputs/bundle/release/app-release.aab'
  foreach ($source in @($apkSource, $bundleSource)) {
    if (-not (Test-Path -LiteralPath $source) -or (Get-Item -LiteralPath $source).Length -eq 0) {
      throw "Expected nonempty release artifact is missing: $source"
    }
  }
  foreach ($destination in @($apkDestination, $bundleDestination, $checksumDestination)) {
    if (Test-Path -LiteralPath $destination) {
      throw "Release artifact appeared during build: $destination. Refusing to overwrite."
    }
  }
  Copy-Item -LiteralPath $apkSource -Destination $apkDestination
  Copy-Item -LiteralPath $bundleSource -Destination $bundleDestination

  $artifacts = @(
    Get-Item -LiteralPath $apkDestination
    Get-Item -LiteralPath $bundleDestination
  )
  $checksums = foreach ($artifact in $artifacts) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $artifact.Name
  }
  Set-Content -LiteralPath $checksumDestination -Value $checksums -Encoding utf8

  Write-Host "Android release package: $distributionDirectory"
  $checksums | ForEach-Object { Write-Host $_ }
} finally {
  Pop-Location
}
