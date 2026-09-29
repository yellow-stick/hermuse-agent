# TEMPORARY helpers of .github/workflows/winapp-probe.yml, removed with it.
# Dot-sourced by each probe step (Windows PowerShell 7 on windows-2025).

$AppDir = Join-Path $env:LOCALAPPDATA 'Programs\Hermuse Agent'
$AppExe = Join-Path $AppDir 'hermuse_app.exe'
$StartMenuLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Hermuse Agent.lnk'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{623CBA2D-B2D8-40B4-B0A3-334510D03899}_is1'
$SupportDir = Join-Path $env:APPDATA 'Yellow Stick\Hermuse Agent'
$Tesseract = 'C:\Program Files\Tesseract-OCR\tesseract.exe'
$Results = [ordered]@{}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('ProbeNative' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ProbeNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, IntPtr extra);
}
'@
}
[void][ProbeNative]::SetProcessDPIAware()

function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  $Results[$Name] = [ordered]@{ status = $(if ($Ok) { 'pass' } else { 'fail' }); detail = $Detail }
  Write-Host ('{0} {1}: {2}' -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail)
}

function Save-Results([string]$Name = 'install') {
  $Results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $env:PROBE "results-$Name.json")
}

function Assert-Results {
  $failed = @($Results.GetEnumerator() | Where-Object { $_.Value.status -ne 'pass' } | ForEach-Object Key)
  if ($failed.Count -gt 0) { throw "failed: $($failed -join ', ')" }
}

function Show-App($Process) {
  $Process.Refresh()
  [void][ProbeNative]::ShowWindow($Process.MainWindowHandle, 3)
  [void][ProbeNative]::SetForegroundWindow($Process.MainWindowHandle)
  Start-Sleep 2
}

# Screenshot of the primary screen as <name>.png, OCR (inverted, 200%) as
# <name>.txt; returns the recognised text.
function Read-Screen([string]$Name) {
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.Size)
  $png = Join-Path $env:PROBE "$Name.png"
  $bitmap.Save($png)
  $graphics.Dispose()
  $bitmap.Dispose()
  $pre = Join-Path $env:RUNNER_TEMP "$Name-ocr.png"
  magick $png -colorspace HSB -channel B -separate +channel -negate -resize 200% $pre
  & $Tesseract $pre (Join-Path $env:PROBE $Name) --psm 11 2>$null | Out-Null
  $text = (Get-Content -LiteralPath (Join-Path $env:PROBE "$Name.txt") | Where-Object { $_.Trim() }) -join "`n"
  Write-Host "--- OCR $Name`n$text"
  return $text
}

# Clicks the centre of the first on-screen line holding $Phrase (OCR words).
function Click-Text([string]$CheckName, [string]$Phrase) {
  [void](Read-Screen "$CheckName-before")
  $pre = Join-Path $env:RUNNER_TEMP "$CheckName-before-ocr.png"
  $rows = & $Tesseract $pre - --psm 11 tsv 2>$null | Select-Object -Skip 1 | ForEach-Object {
    $c = $_ -split "`t"
    if ($c.Count -ge 12 -and $c[11].Trim()) {
      [pscustomobject]@{
        Line = "$($c[2])-$($c[3])-$($c[4])"; Left = [int]$c[6]; Top = [int]$c[7]
        Width = [int]$c[8]; Height = [int]$c[9]; Text = $c[11].Trim()
      }
    }
  }
  $words = $Phrase -split '\s+'
  foreach ($line in ($rows | Group-Object Line)) {
    $w = @($line.Group)
    for ($i = 0; $i -le $w.Count - $words.Count; $i++) {
      $hit = $true
      for ($j = 0; $j -lt $words.Count; $j++) { if ($w[$i + $j].Text -ne $words[$j]) { $hit = $false; break } }
      if (-not $hit) { continue }
      $slice = $w[$i..($i + $words.Count - 1)]
      $left = ($slice | Measure-Object Left -Minimum).Minimum
      $right = ($slice | ForEach-Object { $_.Left + $_.Width } | Measure-Object -Maximum).Maximum
      $top = ($slice | Measure-Object Top -Minimum).Minimum
      $bottom = ($slice | ForEach-Object { $_.Top + $_.Height } | Measure-Object -Maximum).Maximum
      # The OCR image is the screenshot at 200%.
      $x = [int](($left + $right) / 4)
      $y = [int](($top + $bottom) / 4)
      [void][ProbeNative]::SetCursorPos($x, $y)
      Start-Sleep -Milliseconds 300
      [ProbeNative]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
      [ProbeNative]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
      Check $CheckName $true "clicked '$Phrase' at $x,$y"
      return
    }
  }
  Check $CheckName $false "'$Phrase' not found on screen"
}
