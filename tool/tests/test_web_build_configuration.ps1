$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$builderSource = Join-Path $repositoryRoot 'tool/build_web_clients.ps1'
$checksPassed = 0

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
  $script:checksPassed++
}

function New-Fixture {
  $root = Join-Path ([IO.Path]::GetTempPath()) ("web-build-config-" + [guid]::NewGuid().ToString('N'))
  $toolDir = Join-Path $root 'tool'
  $adminDir = Join-Path $root 'build/admin_web'
  New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
  New-Item -ItemType Directory -Path $adminDir -Force | Out-Null

  $builder = Join-Path $toolDir 'build_web_clients.ps1'
  Copy-Item -LiteralPath $builderSource -Destination $builder
  $capture = Join-Path $root 'flutter-args.jsonl'
  $fakeFlutter = Join-Path $root 'fake-flutter.ps1'
  $fakeSource = @'
param()
$record = ConvertTo-Json -InputObject @($args) -Compress
Add-Content -LiteralPath '__CAPTURE_PATH__' -Value $record
$global:LASTEXITCODE = 0
'@
  $fakeSource = $fakeSource.Replace('__CAPTURE_PATH__', $capture)
  [IO.File]::WriteAllText($fakeFlutter, $fakeSource, [Text.UTF8Encoding]::new($false))

  $html = @'
<meta name="description" content="Mobile study data collection for authorized field staff.">
<meta name="application-name" content="Study Collector">
<title>Study Collector</title>
'@
  $manifest = @'
{"name": "Study Collector", "short_name": "Collector", "description": "Mobile study data collection for authorized field staff."}
'@
  [IO.File]::WriteAllText((Join-Path $adminDir 'index.html'), $html, [Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $adminDir 'manifest.json'), $manifest, [Text.UTF8Encoding]::new($false))

  return @{ Root = $root; Builder = $builder; FakeFlutter = $fakeFlutter; Capture = $capture }
}

function Read-FlutterCalls {
  param([string]$CapturePath)
  if (-not (Test-Path -LiteralPath $CapturePath)) { return @() }
  $calls = @()
  foreach ($line in Get-Content -LiteralPath $CapturePath) {
    $parsedArgs = ConvertFrom-Json -InputObject $line
    $calls += [pscustomobject]@{ Args = $parsedArgs }
  }
  return $calls
}

function Invoke-Build {
  param([hashtable]$Fixture, [hashtable]$Parameters)
  $Parameters['FlutterCommand'] = $Fixture.FakeFlutter
  & $Fixture.Builder @Parameters
}

function Remove-Fixture {
  param([hashtable]$Fixture)
  if ($Fixture -and (Test-Path -LiteralPath $Fixture.Root)) {
    Remove-Item -LiteralPath $Fixture.Root -Recurse -Force
  }
}

# Public administrator builds must use the explicit HTTPS origin and must
# never pass collector credentials or collector identity to Flutter.
$fixture = New-Fixture
try {
    $collectorSecret = 'collector-secret-for-regression-check'
    Invoke-Build $fixture @{
      AdminOnly = $true
      PublicRelease = $true
      AdminApiBaseUrl = 'https://admin.example.test'
      LocalApiBaseUrl = 'http://collector.internal:8080'
      CollectorApiKey = $collectorSecret
      CollectorId = 'C123'
    }
    $calls = @(Read-FlutterCalls $fixture.Capture)
    Assert-True ($calls.Count -eq 1) 'AdminOnly should invoke Flutter exactly once.'
    $adminArgs = @($calls[0].Args)
    Assert-True ($adminArgs -contains '--target') 'Public admin build should specify a target.'
    Assert-True ($adminArgs -contains 'lib/admin_main.dart') 'Public admin build should target the admin entrypoint.'
    Assert-True ($adminArgs -contains '--output') 'Public admin build should specify an output directory.'
    Assert-True ($adminArgs -contains 'build/admin_web') 'Public admin build should use the admin output directory.'
    Assert-True ($adminArgs -contains '--dart-define=LOCAL_API_BASE_URL=https://admin.example.test') 'Admin API origin should be passed as a Dart define.'
    Assert-True (-not (($adminArgs -join ' ') -match 'LOCAL_API_KEY|C123|collector-secret-for-regression-check')) 'Public admin build arguments must not contain collector secrets or identity.'
    $updatedHtml = Get-Content -LiteralPath (Join-Path $fixture.Root 'build/admin_web/index.html') -Raw
    Assert-True ($updatedHtml.Contains('<title>Study Admin</title>')) 'Successful build should apply administrator web metadata.'
  } finally {
    Remove-Fixture $fixture
  }

  # Public release validation rejects insecure origins, URL paths, and embedded credentials
  # before invoking Flutter.
  $rejections = @(
    @{ Url = 'http://admin.example.test'; Label = 'HTTP public origin' },
    @{ Url = 'https://admin.example.test/api'; Label = 'admin URL path' },
    @{ Url = 'https://build-user:build-password@admin.example.test'; Label = 'admin URL credentials' }
  )
  foreach ($case in $rejections) {
    $fixture = New-Fixture
    try {
      $message = ''
      try {
        Invoke-Build $fixture @{ AdminOnly = $true; PublicRelease = $true; AdminApiBaseUrl = $case.Url }
      } catch {
        $message = $_.Exception.Message
      }
      Assert-True ($message -match 'AdminApiBaseUrl must be an HTTP\(S\) origin') "$($case.Label) should be rejected with the admin URL validation error."
      Assert-True (@(Read-FlutterCalls $fixture.Capture).Count -eq 0) "$($case.Label) should be rejected before Flutter runs."
    } finally {
      Remove-Fixture $fixture
    }
  }

  # The legacy build still creates both sites, keeps collector defines on the
  # collector invocation only, and falls back to the local API origin for admin.
  $fixture = New-Fixture
  try {
    Invoke-Build $fixture @{
      LocalApiBaseUrl = 'http://localhost:8765'
      CollectorApiKey = 'legacy-collector-key-12345'
      CollectorNumber = 5
      NoPub = $true
    }
    $calls = @(Read-FlutterCalls $fixture.Capture)
    Assert-True ($calls.Count -eq 2) 'Legacy mode should invoke Flutter for collector and admin sites.'
    $collectorArgs = @($calls[0].Args)
    $adminArgs = @($calls[1].Args)
    Assert-True ($collectorArgs -contains 'lib/main.dart') 'First legacy build should target the collector entrypoint.'
    Assert-True ($collectorArgs -contains 'build/collector_web') 'Legacy collector should retain its output directory.'
    Assert-True ($collectorArgs -contains '--dart-define=LOCAL_API_BASE_URL=http://localhost:8765') 'Collector should retain its local API define.'
    Assert-True ($collectorArgs -contains '--dart-define=LOCAL_API_KEY=legacy-collector-key-12345') 'Collector should retain its API key define.'
    Assert-True ($collectorArgs -contains '--dart-define=LOCAL_COLLECTOR_ID=C005') 'CollectorNumber should retain generated collector ID behavior.'
    Assert-True ($collectorArgs -contains '--no-pub' -and $adminArgs -contains '--no-pub') 'NoPub should be passed to both legacy builds.'
    Assert-True ($adminArgs -contains 'lib/admin_main.dart') 'Second legacy build should target the admin entrypoint.'
    Assert-True ($adminArgs -contains '--dart-define=LOCAL_API_BASE_URL=http://localhost:8765') 'Legacy admin API should fall back to LocalApiBaseUrl.'
    Assert-True (-not (($adminArgs -join ' ') -match 'LOCAL_API_KEY|legacy-collector-key-12345|LOCAL_COLLECTOR_ID')) 'Collector defines should not be passed to the legacy admin build.'
  } finally {
    Remove-Fixture $fixture
  }

Write-Host "Web build configuration checks passed: $checksPassed"
