param(
  [string]$DartPath = 'dart',
  [switch]$KeepSyntheticData
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw 'This smoke test is Windows-only.'
}

$serverScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'tool/local_sync_server.dart'
if (-not (Test-Path -LiteralPath $serverScript -PathType Leaf)) {
  throw "Local sync server script not found: $serverScript"
}
$dartCommand = Get-Command $DartPath -ErrorAction Stop
$dartExecutable = $dartCommand.Source
if ([IO.Path]::GetExtension($dartExecutable) -ieq '.bat') {
  $dartExecutable = Join-Path (Split-Path -Parent $dartExecutable) 'dart.exe'
  if (-not (Test-Path -LiteralPath $dartExecutable -PathType Leaf)) {
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $dartCommand.Source)
    $dartExecutable = Join-Path $flutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
  }
}
if (-not (Test-Path -LiteralPath $dartExecutable -PathType Leaf)) {
  throw "Dart executable not found: $dartExecutable"
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$dataDirectory = Join-Path $temporaryRoot ("local-sync-smoke-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dataDirectory | Out-Null

$collectorKey = 'synthetic-collector-' + [guid]::NewGuid().ToString('N')
$adminKey = 'synthetic-admin-' + [guid]::NewGuid().ToString('N')
$isolatedAppData = Join-Path $dataDirectory 'appdata'
New-Item -ItemType Directory -Path $isolatedAppData | Out-Null
$portListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$portListener.Start()
$port = ([Net.IPEndPoint]$portListener.LocalEndpoint).Port
$portListener.Stop()
$baseUrl = "http://127.0.0.1:$port"
$serverProcess = $null
$collectorSessionToken = $null

function Start-IsolatedServer {
  $oldLocalSyncVariables = @{}
  $oldAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
  foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
    if ([string]$entry.Key -like 'LOCAL_SYNC_*') {
      $oldLocalSyncVariables[[string]$entry.Key] = [string]$entry.Value
    }
  }
  try {
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
      if ([string]$name -like 'LOCAL_SYNC_*') {
        [Environment]::SetEnvironmentVariable([string]$name, $null, 'Process')
      }
    }
    [Environment]::SetEnvironmentVariable('LOCAL_SYNC_COLLECTOR_KEY', $collectorKey, 'Process')
    [Environment]::SetEnvironmentVariable('LOCAL_SYNC_ADMIN_KEY', $adminKey, 'Process')
    [Environment]::SetEnvironmentVariable('APPDATA', $isolatedAppData, 'Process')
    return Start-Process -FilePath $dartExecutable `
      -ArgumentList @('--suppress-analytics', 'run', ('"{0}"' -f $serverScript), '--host=127.0.0.1', "--port=$port") `
      -WorkingDirectory $dataDirectory -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput (Join-Path $dataDirectory 'server.stdout.log') `
      -RedirectStandardError (Join-Path $dataDirectory 'server.stderr.log')
  }
  finally {
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
      if ([string]$name -like 'LOCAL_SYNC_*') {
        [Environment]::SetEnvironmentVariable([string]$name, $null, 'Process')
      }
    }
    foreach ($name in $oldLocalSyncVariables.Keys) {
      [Environment]::SetEnvironmentVariable($name, $oldLocalSyncVariables[$name], 'Process')
    }
    [Environment]::SetEnvironmentVariable('APPDATA', $oldAppData, 'Process')
  }
}

function Wait-ForHealth {
  param([Diagnostics.Process]$Process)
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    if ($Process.HasExited) {
      throw "Local sync server exited early with code $($Process.ExitCode)."
    }
    try {
      $health = Invoke-RestMethod -Method Get `
        -Uri "$baseUrl/health" `
        -Headers @{ 'x-local-sync-key' = $adminKey } `
        -TimeoutSec 2
      if ($health.status -in @('ok', 'degraded')) { return $health }
    }
    catch {
      Start-Sleep -Milliseconds 250
    }
  }
  throw 'The isolated local sync server did not become healthy within 10 seconds.'
}

function Stop-IsolatedServer {
  param([Diagnostics.Process]$Process)
  if ($null -ne $Process -and -not $Process.HasExited) {
    # Dart can keep a dartvm.exe child alive. Kill the exact process tree
    # returned by Start-Process so the server releases its isolated directory.
    $killTreeMethod = $Process.GetType().GetMethod('Kill', [Type[]]@([bool]))
    if ($null -ne $killTreeMethod) {
      $null = $killTreeMethod.Invoke($Process, @($true))
    }
    else {
      $null = & taskkill.exe /PID $Process.Id /T /F 2>$null
      if ($LASTEXITCODE -ne 0 -and -not $Process.HasExited) {
        throw "Could not terminate the isolated server process tree (PID $($Process.Id))."
      }
    }
    if (-not $Process.WaitForExit(10000)) {
      throw "The isolated server process did not exit after termination (PID $($Process.Id))."
    }
  }
}

function Invoke-RecordUpload {
  param([hashtable]$Record)
  return Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/records" `
    -Headers @{
      'x-local-sync-key' = $collectorKey
      'x-local-session' = $collectorSessionToken
    } `
    -ContentType 'application/json' `
    -Body ($Record | ConvertTo-Json -Depth 20 -Compress) `
    -TimeoutSec 5
}

function Assert-CollectorCannotReadRecords {
  try {
    $null = Invoke-WebRequest -Method Get `
      -Uri "$baseUrl/records" `
      -Headers @{
        'x-local-sync-key' = $collectorKey
        'x-local-session' = $collectorSessionToken
      } `
      -UseBasicParsing -TimeoutSec 5
    throw 'Collector credentials unexpectedly accessed the admin records route.'
  }
  catch {
    $response = $_.Exception.Response
    if ($null -eq $response -or [int]$response.StatusCode -ne 403) { throw }
  }
}

try {
  Write-Host "Using isolated synthetic data directory: $dataDirectory"
  $serverProcess = Start-IsolatedServer
  $health = Wait-ForHealth -Process $serverProcess
  if ($health.status -notin @('ok', 'degraded') -or $health.records -ne 0) {
    throw "Expected a healthy, empty synthetic store; got status=$($health.status), records=$($health.records)."
  }
  Write-Host 'PASS: health endpoint reports an empty isolated store.'

  $session = Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/collector/session" `
    -Headers @{ 'x-local-sync-key' = $collectorKey } `
    -ContentType 'application/json' `
    -Body (@{ collectorId = 'C001' } | ConvertTo-Json -Compress) `
    -TimeoutSec 5
  $collectorSessionToken = $session.sessionToken
  if ([string]::IsNullOrWhiteSpace($collectorSessionToken)) {
    throw 'The collector session endpoint did not return a session token.'
  }

  Assert-CollectorCannotReadRecords
  Write-Host 'PASS: collector key is denied access to the admin records route.'

  $recordId = 'SMOKE-' + [guid]::NewGuid().ToString('N')
  $record = @{
    id = $recordId
    idempotencyKey = 'smoke-upload-' + [guid]::NewGuid().ToString('N')
    participant = @{
      studyId = 'P900000001'
      name = 'Synthetic Smoke Participant'
      indianPhone = '+19995550001'
    }
    visitNumber = 1
    collectorId = 'C001'
    createdAt = [DateTime]::UtcNow.ToString('o')
    updatedAt = [DateTime]::UtcNow.ToString('o')
    status = 'submitted'
    syncState = 'pending'
    reviewState = 'pending'
    revision = 1
    confirmation = @{
      name = 'Synthetic Smoke Participant'
      indianPhone = '+19995550001'
      visitNumber = 1
      confirmedAt = [DateTime]::UtcNow.ToString('o')
    }
    stepTwoMeasurement = $null
    stepTwoPlaceholderNote = $null
    questionnaire = $null
    submittedAt = [DateTime]::UtcNow.ToString('o')
  }

  $firstUpload = Invoke-RecordUpload -Record $record
  if ($firstUpload.id -ne $recordId -or $firstUpload.syncState -ne 'synced') {
    throw 'The server did not acknowledge the synthetic record as synced.'
  }
  $retry = Invoke-RecordUpload -Record $record
  if ($retry.id -ne $recordId) {
    throw 'The same idempotency key did not return the originally accepted record.'
  }
  $adminRecords = Invoke-RestMethod -Method Get `
    -Uri "$baseUrl/records" `
    -Headers @{ 'x-local-sync-key' = $adminKey } `
    -TimeoutSec 5
  if (@($adminRecords).Count -ne 1 -or $adminRecords[0].id -ne $recordId) {
    throw 'Admin visibility did not show exactly one synthetic record after retry.'
  }
  Write-Host 'PASS: upload, idempotent retry, and admin visibility work.'

  Stop-IsolatedServer -Process $serverProcess
  $serverProcess = Start-IsolatedServer
  $healthAfterRestart = Wait-ForHealth -Process $serverProcess
  if ($healthAfterRestart.records -ne 1) {
    throw "Expected one durable synthetic record after restart; got $($healthAfterRestart.records)."
  }
  $restartRetry = Invoke-RecordUpload -Record $record
  $recordsAfterRestartRetry = Invoke-RestMethod -Method Get `
    -Uri "$baseUrl/records" `
    -Headers @{ 'x-local-sync-key' = $adminKey } `
    -TimeoutSec 5
  if ($restartRetry.id -ne $recordId -or @($recordsAfterRestartRetry).Count -ne 1) {
    throw 'Retry after restart was not idempotent or the stored record was not preserved.'
  }
  Write-Host 'PASS: the same synthetic upload remains durable and idempotent after restart.'
  Write-Host 'Synthetic local sync server smoke test passed.'
}
catch {
  foreach ($logName in @('server.stdout.log', 'server.stderr.log')) {
    $logPath = Join-Path $dataDirectory $logName
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
      $logContents = Get-Content -LiteralPath $logPath -Raw
      if (-not [string]::IsNullOrWhiteSpace($logContents)) {
        Write-Host "--- $logName ---"
        Write-Host $logContents
      }
    }
  }
  throw
}
finally {
  Stop-IsolatedServer -Process $serverProcess
  if (-not $KeepSyntheticData) {
    $resolvedDataDirectory = [IO.Path]::GetFullPath($dataDirectory)
    if ($resolvedDataDirectory.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedDataDirectory).StartsWith('local-sync-smoke-', [StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolvedDataDirectory -Recurse -Force
    }
  }
  else {
    Write-Host "Kept synthetic-only server data at: $dataDirectory"
  }
}
