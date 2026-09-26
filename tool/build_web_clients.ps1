param(
  [string]$FlutterCommand = "flutter",
  [string]$LocalApiBaseUrl = "",
  [string]$AdminApiBaseUrl = "",
  [switch]$AdminOnly,
  [switch]$PublicRelease,
  [switch]$NoPub,
  [string]$CollectorApiKey = "",
  [string]$CollectorId = "",
  [int]$CollectorNumber = 0
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot

$hasUrl = -not [string]::IsNullOrWhiteSpace($LocalApiBaseUrl)
$hasCollectorKey = -not [string]::IsNullOrWhiteSpace($CollectorApiKey)
if (-not $AdminOnly -and $hasUrl -ne $hasCollectorKey) {
  throw "LocalApiBaseUrl and CollectorApiKey must be supplied together."
}
if ($hasCollectorKey -and $CollectorApiKey.Length -lt 16) {
  throw "CollectorApiKey must be at least 16 characters."
}

if ($CollectorNumber -lt 0) {
  throw "CollectorNumber must be greater than or equal to 0."
}
if ([string]::IsNullOrWhiteSpace($CollectorId) -and $CollectorNumber -gt 0) {
  $CollectorId = "C{0:D3}" -f $CollectorNumber
}
if (-not [string]::IsNullOrWhiteSpace($CollectorId)) {
  $CollectorId = $CollectorId.Trim()
}

$collectorDefines = @()
$adminDefines = @()
$dependencyArgs = @()
if ($NoPub) { $dependencyArgs += '--no-pub' }
if ([string]::IsNullOrWhiteSpace($AdminApiBaseUrl)) {
  $AdminApiBaseUrl = $LocalApiBaseUrl
}
if ($PublicRelease -and [string]::IsNullOrWhiteSpace($AdminApiBaseUrl)) {
  throw "PublicRelease requires an explicit AdminApiBaseUrl."
}
if (-not [string]::IsNullOrWhiteSpace($AdminApiBaseUrl)) {
  $adminUri = $null
  if (-not [Uri]::TryCreate($AdminApiBaseUrl, [UriKind]::Absolute, [ref]$adminUri) -or
      $adminUri.Scheme -notin @('http', 'https') -or
      -not [string]::IsNullOrEmpty($adminUri.UserInfo) -or
      -not [string]::IsNullOrEmpty($adminUri.Query) -or
      -not [string]::IsNullOrEmpty($adminUri.Fragment) -or
      $adminUri.AbsolutePath -ne '/' -or
      ($PublicRelease -and $adminUri.Scheme -ne 'https')) {
    throw "AdminApiBaseUrl must be an HTTP(S) origin without credentials, path, query, or fragment; public releases require HTTPS."
  }
  $adminDefines += "--dart-define=LOCAL_API_BASE_URL=$AdminApiBaseUrl"
}
if ($PublicRelease -and -not $AdminOnly) {
  throw "Use -AdminOnly for public deployment; collector credentials must not be embedded in a public website."
}
if ($hasUrl) {
  $collectorDefines += @(
    "--dart-define=LOCAL_API_BASE_URL=$LocalApiBaseUrl",
    "--dart-define=LOCAL_API_KEY=$CollectorApiKey"
  )
}
if (-not [string]::IsNullOrWhiteSpace($CollectorId)) {
  $collectorDefines += "--dart-define=LOCAL_COLLECTOR_ID=$CollectorId"
}

function Replace-RequiredText {
  param(
    [string]$Path,
    [hashtable]$Replacements
  )

  $content = Get-Content -LiteralPath $Path -Raw
  foreach ($source in $Replacements.Keys) {
    if (-not $content.Contains($source)) {
      throw "Expected web metadata was not found in ${Path}: $source"
    }
    $content = $content.Replace($source, $Replacements[$source])
  }

  [System.IO.File]::WriteAllText(
    $Path,
    $content,
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Update-AdminWebMetadata {
  $adminOutput = Join-Path $projectDirectory "build/admin_web"
  Replace-RequiredText (Join-Path $adminOutput "index.html") @{
    'content="Mobile study data collection for authorized field staff."' = 'content="Secure browser portal for authorized study administrators."'
    'content="Study Collector"' = 'content="Study Admin"'
    '<title>Study Collector</title>' = '<title>Study Admin</title>'
  }
  Replace-RequiredText (Join-Path $adminOutput "manifest.json") @{
    '"name": "Study Collector"' = '"name": "Study Admin"'
    '"short_name": "Collector"' = '"short_name": "Study Admin"'
    '"description": "Mobile study data collection for authorized field staff."' = '"description": "Secure browser portal for authorized study administrators."'
  }
}

Push-Location $projectDirectory

try {
  if (-not $AdminOnly) {
    & $FlutterCommand build web --release --target lib/main.dart --output build/collector_web @collectorDefines @dependencyArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Collector website build failed."
    }
  }

  & $FlutterCommand build web --release --target lib/admin_main.dart --output build/admin_web @adminDefines @dependencyArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Admin website build failed."
  }
  Update-AdminWebMetadata

  if (-not $AdminOnly) { Write-Host "Collector website: build/collector_web" }
  Write-Host "Admin website:     build/admin_web"
} finally {
  Pop-Location
}
