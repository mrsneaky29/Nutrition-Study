param(
  [Parameter(Mandatory = $true)][string]$ApkPath,
  [Parameter(Mandatory = $true)][string]$BuildToolsDirectory,
  [int]$ExpectedBuildNumber = 5,
  [string]$ExpectedVersion = '1.0.0',
  [string]$ExpectedCertificateSha256 = '36b7e26028c228305181b060a64e9e3d5e72747236214b7ec553d007a58cefb9'
)

$ErrorActionPreference = 'Stop'
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$signer = Join-Path $BuildToolsDirectory 'apksigner.bat'
$aapt = Join-Path $BuildToolsDirectory 'aapt.exe'
foreach ($tool in @($signer, $aapt)) {
  if (-not (Test-Path -LiteralPath $tool)) { throw "Missing Android verification tool: $tool" }
}
$signature = @(& $signer verify --verbose --print-certs $apk 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
$certificates = @($signature | Select-String 'certificate SHA-256 digest:\s*([0-9a-fA-F]+)' | ForEach-Object { $_.Matches[0].Groups[1].Value.ToLowerInvariant() })
if ($certificates.Count -ne 1 -or $certificates[0] -ne $ExpectedCertificateSha256.ToLowerInvariant()) {
  throw 'APK signing certificate does not match the expected study release key.'
}
$badging = @(& $aapt dump badging $apk 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Cannot read APK version metadata.' }
$metadata = $badging | Select-String "^package: name='org.nutritionstudy.project2' versionCode='$ExpectedBuildNumber' versionName='$([regex]::Escape($ExpectedVersion))'"
if (-not $metadata) { throw 'APK application ID or version does not match the expected release.' }
$manifest = @(& $aapt dump xmltree $apk AndroidManifest.xml 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect APK manifest.' }
if ($manifest | Select-String 'usesCleartextTraffic.*0xffffffff') {
  throw 'Public release APK explicitly allows cleartext traffic.'
}
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Verified study APK $ExpectedVersion+$ExpectedBuildNumber"
Write-Host "Signing certificate: $($certificates[0])"
Write-Host "SHA256: $hash"
