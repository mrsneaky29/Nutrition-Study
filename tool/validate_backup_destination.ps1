param(
  [Parameter(Mandatory = $true)]
  [string]$Destination
)

$ErrorActionPreference = 'Stop'

function Deny([string]$Reason) {
  [Console]::Error.WriteLine("Backup destination rejected: $Reason")
  exit 1
}

if (-not [System.IO.Path]::IsPathRooted($Destination)) {
  Deny 'Use an absolute path on a removable USB drive or a remote network share.'
}

try {
  $fullPath = [System.IO.Path]::GetFullPath($Destination)
  $root = [System.IO.Path]::GetPathRoot($fullPath)
} catch {
  Deny "Invalid destination path: $($_.Exception.Message)"
}

if ($root.StartsWith('\\')) {
  $server = $root.TrimStart([char]'\').Split([char]'\')[0]
  $serverLower = $server.ToLowerInvariant()
  $computerLower = $env:COMPUTERNAME.ToLowerInvariant()
  if ($serverLower -in @('localhost', '127.0.0.1', '[::1]', '.', $computerLower) -or
      $serverLower.StartsWith("$computerLower.") -or
      $serverLower.StartsWith('127.')) {
    Deny 'A share hosted by this computer is not an off-PC backup.'
  }
  try {
    $localAddresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName())
    $shareAddresses = [System.Net.Dns]::GetHostAddresses($server)
    foreach ($address in $shareAddresses) {
      if ([System.Net.IPAddress]::IsLoopback($address) -or
          $localAddresses.IPAddressToString -contains $address.IPAddressToString) {
        Deny 'A share hosted by this computer is not an off-PC backup.'
      }
    }
  } catch {
    Deny "The network share host could not be verified: $($_.Exception.Message)"
  }
  if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    Deny 'The remote network share is unavailable.'
  }
  Write-Output "Verified remote network share: $root"
  exit 0
}

try {
  $drive = [System.IO.DriveInfo]::new($root)
  if (-not $drive.IsReady) { Deny "Drive $root is not ready." }
  if ($drive.DriveType -eq [System.IO.DriveType]::Removable -or
      $drive.DriveType -eq [System.IO.DriveType]::Network) {
    Write-Output "Verified removable or mapped network drive: $root"
    exit 0
  }

  # Many USB HDDs and SSDs report DriveType=Fixed. Check their physical bus.
  $letter = $root.Substring(0, 1)
  $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
  $disks = @($partition | Get-Disk -ErrorAction Stop)
  if ($disks.Count -eq 1 -and $disks[0].BusType -eq 'USB') {
    Write-Output "Verified USB-attached disk: $root"
    exit 0
  }
  Deny "Drive $root is not identified as removable, USB, or remote network storage."
} catch {
  Deny "Could not verify that $root is off-PC storage: $($_.Exception.Message)"
}
