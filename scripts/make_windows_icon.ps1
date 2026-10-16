# Writes Resources/ScreenshotTool.ico, the Windows app icon, from the transparent 1024 px artwork.
# The app exe embeds it (Source/ScreenshotTool.rc), so the taskbar and Alt+Tab show it, and
# stage_release.ps1 stages the same file for the launcher, the Start menu shortcut and the MSI.
# Run it again whenever Resources/ScreenshotToolIcon.png changes, and commit the result.
param(
  [string]$SourcePath = (Join-Path $PSScriptRoot "..\Resources\ScreenshotToolIcon.png"),
  [string]$DestinationPath = (Join-Path $PSScriptRoot "..\Resources\ScreenshotTool.ico")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Windows' usual icon sizes, each stored as a PNG.
$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$images = [System.Collections.Generic.List[byte[]]]::new()
$source = [System.Drawing.Image]::FromFile((Resolve-Path $SourcePath))
try {
  foreach ($size in $sizes) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
      $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
      $graphics.DrawImage($source, 0, 0, $size, $size)
    } finally {
      $graphics.Dispose()
    }
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    $images.Add($stream.ToArray())
    $stream.Dispose()
  }
} finally {
  $source.Dispose()
}

$file = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($file)
$writer.Write([uint16]0)              # reserved
$writer.Write([uint16]1)              # type: icon
$writer.Write([uint16]$sizes.Count)
$offset = 6 + (16 * $sizes.Count)
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $edge = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }   # 0 means 256
  $writer.Write([byte]$edge)
  $writer.Write([byte]$edge)
  $writer.Write([byte]0)              # no palette
  $writer.Write([byte]0)              # reserved
  $writer.Write([uint16]1)            # colour planes
  $writer.Write([uint16]32)           # bits per pixel
  $writer.Write([uint32]$images[$i].Length)
  $writer.Write([uint32]$offset)
  $offset += $images[$i].Length
}
foreach ($image in $images) {
  $writer.Write($image)
}
$writer.Flush()
[System.IO.File]::WriteAllBytes([System.IO.Path]::GetFullPath($DestinationPath), $file.ToArray())
$writer.Dispose()
Write-Host "Wrote Windows icon: $DestinationPath"
