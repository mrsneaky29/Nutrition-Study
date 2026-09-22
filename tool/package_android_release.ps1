param(
  [string]$FlutterCommand = "flutter",
  [string]$BuildName = "1.0.0",
  [int]$BuildNumber = 1,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot
$keyProperties = Join-Path $projectDirectory "android/key.properties"
$keystore = Join-Path $projectDirectory "android/app/study-release.jks"
$distributionDirectory = Join-Path $projectDirectory "dist/android"

if (-not (Test-Path -LiteralPath $keyProperties)) {
  throw "Missing android/key.properties. Create and back up the release signing key before packaging."
}
if (-not (Test-Path -LiteralPath $keystore)) {
  throw "Missing android/app/study-release.jks. Updates require the same signing key."
}
if ($BuildNumber -lt 1) {
  throw "BuildNumber must be at least 1."
}

Push-Location $projectDirectory
try {
  if (-not $SkipBuild) {
    & $FlutterCommand build apk --release --target lib/main.dart --build-name $BuildName --build-number $BuildNumber
    if ($LASTEXITCODE -ne 0) { throw "Release APK build failed." }

    & $FlutterCommand build appbundle --release --target lib/main.dart --build-name $BuildName --build-number $BuildNumber
    if ($LASTEXITCODE -ne 0) { throw "Release App Bundle build failed." }
  }

  New-Item -ItemType Directory -Force -Path $distributionDirectory | Out-Null
  $apkName = "study-collector-$BuildName+$BuildNumber.apk"
  $bundleName = "study-collector-$BuildName+$BuildNumber.aab"
  Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-release.apk" -Destination (Join-Path $distributionDirectory $apkName) -Force
  Copy-Item -LiteralPath "build/app/outputs/bundle/release/app-release.aab" -Destination (Join-Path $distributionDirectory $bundleName) -Force

  $artifacts = @(
    Get-Item -LiteralPath (Join-Path $distributionDirectory $apkName)
    Get-Item -LiteralPath (Join-Path $distributionDirectory $bundleName)
  )
  $checksums = foreach ($artifact in $artifacts) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $artifact.Name
  }
  Set-Content -LiteralPath (Join-Path $distributionDirectory "SHA256SUMS.txt") -Value $checksums -Encoding utf8

  Write-Host "Android release package: $distributionDirectory"
  $checksums | ForEach-Object { Write-Host $_ }
} finally {
  Pop-Location
}
