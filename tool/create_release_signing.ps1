param(
  [string]$KeytoolPath = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot
$keystore = Join-Path $projectDirectory "android/app/study-release.jks"
$keyProperties = Join-Path $projectDirectory "android/key.properties"
$backupDirectory = Join-Path $projectDirectory "private-release-signing-backup"
$backupKeystore = Join-Path $backupDirectory "study-release.jks"
$backupProperties = Join-Path $backupDirectory "key.properties"

if (-not (Test-Path -LiteralPath $KeytoolPath)) {
  throw "keytool was not found at $KeytoolPath"
}
if ((Test-Path -LiteralPath $keystore) -or (Test-Path -LiteralPath $keyProperties)) {
  throw "Release signing files already exist. Refusing to replace the key required for future updates."
}

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$password = [Convert]::ToBase64String($bytes).Replace("+", "A").Replace("/", "B").TrimEnd("=")

& $KeytoolPath -genkeypair -v `
  -keystore $keystore `
  -storepass $password `
  -keypass $password `
  -alias "study-release" `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -dname "CN=Nutrition Study, OU=Research, O=Nutrition Study, L=Hyderabad, ST=Telangana, C=IN"
if ($LASTEXITCODE -ne 0) {
  throw "Release key generation failed."
}

$properties = @(
  "storePassword=$password"
  "keyPassword=$password"
  "keyAlias=study-release"
  "storeFile=study-release.jks"
)
Set-Content -LiteralPath $keyProperties -Value $properties -Encoding utf8

New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null
Copy-Item -LiteralPath $keystore -Destination $backupKeystore
Copy-Item -LiteralPath $keyProperties -Destination $backupProperties

Write-Host "Release signing key created."
Write-Host "Private backup: $backupDirectory"
Write-Host "Keep this directory private and copy it to a second secure location."
