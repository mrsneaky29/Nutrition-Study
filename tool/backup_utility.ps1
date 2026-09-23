param(
  [ValidateSet('Backup', 'Restore', 'Recover', 'Verify', 'SelfTest')]
  [string]$Action = 'Backup',

  [string]$Destination = '',

  [string]$BackupPath = '',

  [string]$Source = '.local_data',

  [string]$Target = '.local_data',

  [string]$Label = '',

  [switch]$ConfirmOverwrite
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $PSScriptRoot

switch ($Action) {
  'Backup' {
    if ([string]::IsNullOrWhiteSpace($Destination)) {
      Write-Host "ERROR: Missing required -Destination parameter for off-device backup." -ForegroundColor Red
      Write-Host "Please specify an external target path (e.g. -Destination 'E:\StudyBackups' or '\\Server\Backups')."
      Write-Host "A same-PC copy or .bak snapshot does not protect against physical hard drive failure or PC loss."
      Write-Host ""
      Write-Host "Usage:"
      Write-Host "  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Backup -Destination 'E:\StudyBackups'"
      Write-Host "  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Backup -Destination 'E:\StudyBackups' -Label 'evening_sync'"
      exit 1
    }

    & (Join-Path $PSScriptRoot 'validate_backup_destination.ps1') -Destination $Destination
    if ($LASTEXITCODE -ne 0) { exit 1 }

    $dartArgs = @('run', 'tool/backup_utility.dart', 'backup', "--destination=$Destination")
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
      $dartArgs += "--source=$Source"
    }
    if (-not [string]::IsNullOrWhiteSpace($Label)) {
      $dartArgs += "--label=$Label"
    }
  }

  'Verify' {
    if ([string]::IsNullOrWhiteSpace($BackupPath)) {
      Write-Host "ERROR: Missing required -BackupPath parameter for verification." -ForegroundColor Red
      Write-Host "Please specify the backup directory to verify (e.g. -BackupPath 'E:\StudyBackups\backup_20260923_180000')."
      Write-Host ""
      Write-Host "Usage:"
      Write-Host "  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Verify -BackupPath 'E:\StudyBackups\backup_20260923_180000'"
      exit 1
    }

    $dartArgs = @('run', 'tool/backup_utility.dart', 'verify', "--backup=$BackupPath")
  }

  'Restore' {
    if ([string]::IsNullOrWhiteSpace($BackupPath)) {
      Write-Host "ERROR: Missing required -BackupPath parameter for restore." -ForegroundColor Red
      Write-Host "Please specify the backup directory to restore from (e.g. -BackupPath 'E:\StudyBackups\backup_20260923_180000')."
      Write-Host ""
      Write-Host "Usage:"
      Write-Host "  powershell -ExecutionPolicy Bypass -File tool/backup_utility.ps1 -Action Restore -BackupPath 'E:\StudyBackups\backup_20260923_180000' -ConfirmOverwrite"
      exit 1
    }

    $dartArgs = @('run', 'tool/backup_utility.dart', 'restore', "--backup=$BackupPath")
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
      $dartArgs += "--target=$Target"
    }
    if ($ConfirmOverwrite) {
      $dartArgs += '--confirm-overwrite'
    }
  }

  'Recover' {
    $dartArgs = @('run', 'tool/backup_utility.dart', 'recover', "--target=$Target")
  }

  'SelfTest' {
    $dartArgs = @('run', 'tool/backup_utility.dart', 'test')
  }
}

Push-Location $projectDirectory
try {
  & dart @dartArgs
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

if ($null -eq $exitCode) {
  $exitCode = 0
}

exit $exitCode
