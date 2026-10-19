# Windows PowerShell 5.1: draw the README sample, a fictional web app's security settings page, 860x520.
param([string]$Out = "$PSScriptRoot\security-settings.png")
Add-Type -AssemblyName System.Drawing
$W = 860; $H = 520
$b = New-Object Drawing.Bitmap $W, $H; $g = [Drawing.Graphics]::FromImage($b)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
function C($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
function Br($hex) { New-Object Drawing.SolidBrush (C $hex) }
function F($size, $style = 'Regular') { New-Object Drawing.Font 'Segoe UI', $size, ([Drawing.FontStyle]$style), ([Drawing.GraphicsUnit]::Pixel) }
function T($s, $font, $hex, $x, $y) { $g.DrawString($s, $font, (Br $hex), [single]$x, [single]$y) }
function RR($x, $y, $w, $h, $r) { $p = New-Object Drawing.Drawing2D.GraphicsPath; $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90); $p.CloseFigure(); $p }
function Box($x, $y, $w, $h, $r, $fill, $line) { $p = RR $x $y $w $h $r; if ($fill) { $g.FillPath((Br $fill), $p) }; if ($line) { $g.DrawPath((New-Object Drawing.Pen (C $line), 1), $p) } }

$g.Clear((C '#f6f7f9'))
# Top bar
$g.FillRectangle((Br '#ffffff'), 0, 0, $W, 52); $g.DrawLine((New-Object Drawing.Pen (C '#e3e6ea')), 0, 52, $W, 52)
Box 20 15 22 22 6 '#5b5bd6' $null; T 'P' (F 14 'Bold') '#ffffff' 25.5 17
T 'Pinecrest' (F 16 'Bold') '#1c2024' 50 14
Box 300 13 260 26 13 '#f1f3f5' $null; T 'Search settings' (F 13) '#8b9198' 318 17
$g.FillEllipse((Br '#f0b35a'), 806, 12, 28, 28); T 'AR' (F 11 'Bold') '#ffffff' 811 18
# Sidebar
$g.FillRectangle((Br '#ffffff'), 0, 53, 190, $H - 53); $g.DrawLine((New-Object Drawing.Pen (C '#e3e6ea')), 190, 53, 190, $H)
T 'SETTINGS' (F 11 'Bold') '#8b9198' 22 72
$items = 'Profile', 'Security', 'Notifications', 'Billing', 'API keys', 'Team'
for ($i = 0; $i -lt $items.Count; $i++) { $y = 96 + 36 * $i
  if ($items[$i] -eq 'Security') { Box 12 $y 166 30 8 '#ededfc' $null; $g.FillRectangle((Br '#5b5bd6'), 12, $y + 7, 3, 16); T $items[$i] (F 14 'Bold') '#3e3eb8' 28 ($y + 5) }
  else { T $items[$i] (F 14) '#3a3f45' 28 ($y + 5) } }
# Main
T 'Security' (F 24 'Bold') '#1c2024' 222 70
T 'Manage how you sign in and keep your account safe.' (F 13) '#6b7178' 223 104
Box 222 136 610 236 10 '#ffffff' '#e3e6ea'
$rows = @(@('Email', 'alex.rivera@example.com'), @('Password', 'Last changed 3 months ago'), @('API key', 'pcst_7f3a9c1e2b8d4f60a5e1c9'))
for ($i = 0; $i -lt 3; $i++) { $y = 136 + 56 * $i
  if ($i -gt 0) { $g.DrawLine((New-Object Drawing.Pen (C '#eef0f2')), 238, $y, 816, $y) }
  T $rows[$i][0] (F 13 'Bold') '#3a3f45' 242 ($y + 18)
  $vf = if ($i -eq 2) { New-Object Drawing.Font 'Consolas', 13, ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel) } else { F 13 }
  T $rows[$i][1] $vf '#1c2024' 360 ($y + 18)
  Box 742 ($y + 13) 72 30 6 '#ffffff' '#d5d9de'; T $(if ($i -eq 2) { 'Rotate' } else { 'Change' }) (F 13) '#1c2024' $(if ($i -eq 2) { 757 } else { 754 }) ($y + 19) }
# Two-factor row
$y = 304; $g.DrawLine((New-Object Drawing.Pen (C '#eef0f2')), 238, $y, 816, $y)
T 'Two-factor authentication' (F 13 'Bold') '#3a3f45' 242 ($y + 14)
T 'Off. Your account is protected by your password only.' (F 12) '#b4542b' 242 ($y + 36)
Box 772 ($y + 21) 42 24 12 '#d5d9de' $null; $g.FillEllipse((Br '#ffffff'), 775, $y + 24, 18, 18)
# Recent sign-ins
T 'Recent sign-ins' (F 15 'Bold') '#1c2024' 222 392
Box 222 420 610 76 10 '#ffffff' '#e3e6ea'
T ('Chrome on Windows  ' + [char]0xB7 + '  Austin, TX') (F 13) '#1c2024' 242 432; T 'Now' (F 13) '#2f8f5b' 780 432
$g.DrawLine((New-Object Drawing.Pen (C '#eef0f2')), 238, 458, 816, 458)
T ('Safari on iPhone  ' + [char]0xB7 + '  Denver, CO') (F 13) '#1c2024' 242 467; T '2 days ago' (F 13) '#6b7178' 750 467
$g.Dispose(); $b.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); "wrote $Out"
