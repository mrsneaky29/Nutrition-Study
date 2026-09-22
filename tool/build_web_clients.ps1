param(
  [string]$FlutterCommand = "flutter",
  [string]$LocalApiBaseUrl = "",
  [string]$LocalApiKey = ""
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($LocalApiBaseUrl) -ne [string]::IsNullOrWhiteSpace($LocalApiKey)) {
  throw "LocalApiBaseUrl and LocalApiKey must be supplied together."
}

$localDefines = @()
if (-not [string]::IsNullOrWhiteSpace($LocalApiBaseUrl)) {
  $localDefines = @(
    "--dart-define=LOCAL_API_BASE_URL=$LocalApiBaseUrl",
    "--dart-define=LOCAL_API_KEY=$LocalApiKey"
  )
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
  & $FlutterCommand build web --release --target lib/main.dart --output build/collector_web @localDefines
  if ($LASTEXITCODE -ne 0) {
    throw "Collector website build failed."
  }

  & $FlutterCommand build web --release --target lib/admin_main.dart --output build/admin_web @localDefines
  if ($LASTEXITCODE -ne 0) {
    throw "Admin website build failed."
  }
  Update-AdminWebMetadata

  Write-Host "Collector website: build/collector_web"
  Write-Host "Admin website:     build/admin_web"
} finally {
  Pop-Location
}
