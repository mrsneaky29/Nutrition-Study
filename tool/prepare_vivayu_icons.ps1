param([Parameter(Mandatory=$true)][string]$SourceImage)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$assetRoot = Join-Path $projectRoot 'assets/branding'
New-Item -ItemType Directory -Force -Path $assetRoot | Out-Null
$master = Join-Path $assetRoot 'vivayu-original.png'
if (!(Test-Path -LiteralPath $master)) {
  Copy-Item -LiteralPath $SourceImage -Destination $master
}
$source = [System.Drawing.Bitmap]::new($master)
try {
  # Find the unchanged artwork against the supplied black backdrop.
  $left=$source.Width; $top=$source.Height; $right=0; $bottom=0
  for($y=0; $y -lt $source.Height; $y++) {
    for($x=0; $x -lt $source.Width; $x++) {
      $pixel=$source.GetPixel($x,$y)
      if($pixel.R -gt 12 -or $pixel.G -gt 12 -or $pixel.B -gt 12) {
        $left=[Math]::Min($left,$x); $top=[Math]::Min($top,$y)
        $right=[Math]::Max($right,$x); $bottom=[Math]::Max($bottom,$y)
      }
    }
  }
  if($left -ge $right){throw 'Artwork bounds not found'}
  $crop=[System.Drawing.Rectangle]::new($left,$top,$right-$left+1,$bottom-$top+1)
  function Write-Icon([int]$Size,[double]$ArtworkFraction,[string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    $canvas=[System.Drawing.Bitmap]::new($Size,$Size)
    $graphics=[System.Drawing.Graphics]::FromImage($canvas)
    try {
      $graphics.Clear([System.Drawing.Color]::Black)
      $graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $scale=$Size*$ArtworkFraction/[Math]::Max($crop.Width,$crop.Height)
      $w=[int][Math]::Round($crop.Width*$scale); $h=[int][Math]::Round($crop.Height*$scale)
      $destinationRect=[System.Drawing.Rectangle]::new([int](($Size-$w)/2),[int](($Size-$h)/2),$w,$h)
      $graphics.DrawImage($source,$destinationRect,$crop,[System.Drawing.GraphicsUnit]::Pixel)
      $canvas.Save($Destination,[System.Drawing.Imaging.ImageFormat]::Png)
    } finally {$graphics.Dispose(); $canvas.Dispose()}
  }
  Write-Icon 1024 0.64 (Join-Path $assetRoot 'vivayu-icon-1024.png')
  # 46dp-wide artwork inside the 108dp adaptive layer fits the 66dp safe circle.
  foreach($density in @(@('mdpi',48,108),@('hdpi',72,162),@('xhdpi',96,216),@('xxhdpi',144,324),@('xxxhdpi',192,432))) {
    $resourceRoot=Join-Path $projectRoot "android/app/src/main/res/mipmap-$($density[0])"
    Write-Icon $density[1] 0.64 (Join-Path $resourceRoot 'vivayu_launcher.png')
    Write-Icon $density[2] (46.0/108.0) (Join-Path $resourceRoot 'vivayu_launcher_foreground.png')
  }
  foreach($size in @(192,512)) {
    Write-Icon $size 0.64 (Join-Path $projectRoot "web/icons/Vivayu-$size.png")
  }
  Write-Icon 32 0.64 (Join-Path $projectRoot 'web/vivayu-favicon.png')
  Write-Host "Artwork preserved: $($source.Width)x$($source.Height); crop bounds $crop"
  Write-Host "Master icon: $assetRoot/vivayu-icon-1024.png"
} finally {$source.Dispose()}
