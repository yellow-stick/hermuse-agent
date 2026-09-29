# Shared helpers for the Windows release scripts (build-release.ps1, sign.ps1),
# dot-sourced by both. PowerShell 7.
#
# Every external download is pinned in tool/release/toolchain.lock.json and
# refused on any SHA-256 drift.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$HermuseWindowsDir = Split-Path -Parent $PSScriptRoot
$HermuseRepo = Split-Path -Parent (Split-Path -Parent $HermuseWindowsDir)
$HermuseLock = Join-Path $HermuseRepo 'tool/release/toolchain.lock.json'

# Identity. The installer AppId never changes: it keys upgrades and the
# per-user uninstall entry.
$HermuseAppName = 'Hermuse Agent'
$HermuseAppId = 'com.yellowstick.hermuse_app'
$HermuseInstallerAppId = '{623CBA2D-B2D8-40B4-B0A3-334510D03899}'
$HermuseBinary = 'hermuse_app.exe'
$HermuseIcon = Join-Path $HermuseRepo 'apps/hermuse_app/windows/runner/resources/app_icon.ico'

# CLIProxyAPI slot next to the executable (CliproxyBinary.locate, Windows).
$HermuseCliproxyPlatform = 'windows-amd64'
$HermuseBundleCliproxy = 'cliproxy.exe'

function Write-HermuseLog([string]$Message) { Write-Host "==> $Message" }

function Stop-Hermuse([string]$Message) { throw "error: $Message" }

# Get-LockValue <dotted path>: value from toolchain.lock.json; missing/null is fatal.
function Get-LockValue([string]$Path) {
  $node = Get-Content -Raw -LiteralPath $HermuseLock | ConvertFrom-Json
  foreach ($key in $Path.Split('.')) {
    $property = $node.PSObject.Properties[$key]
    if ($null -eq $property -or $null -eq $property.Value) {
      Stop-Hermuse "toolchain.lock.json has no .$Path"
    }
    $node = $property.Value
  }
  return $node
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-Sha256([string]$Path, [string]$Expected, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Hermuse "$Label missing: $Path" }
  $actual = Get-Sha256 $Path
  if ($actual -ne $Expected.ToLowerInvariant()) {
    Stop-Hermuse "$Label SHA-256 mismatch for ${Path}: expected $Expected, got $actual"
  }
}

# Runs a native command; a non-zero exit is fatal.
function Invoke-Native([string]$FilePath, [string[]]$Arguments) {
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    Stop-Hermuse "$FilePath $($Arguments -join ' ') failed (exit $LASTEXITCODE)"
  }
}

# Downloads caches shared by the release scripts (build-release.ps1 points
# HERMUSE_TOOLS_CACHE into its work directory).
function Get-HermuseToolsCache {
  $cache = $env:HERMUSE_TOOLS_CACHE
  if (-not $cache) { $cache = Join-Path ([IO.Path]::GetTempPath()) 'hermuse-tools-cache' }
  New-Item -ItemType Directory -Force -Path $cache | Out-Null
  return $cache
}

# Get-PinnedFile <url> <sha256> <destination> <label>: download once, verify on every use.
function Get-PinnedFile([string]$Url, [string]$Sha256, [string]$Destination, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    $partial = "$Destination.partial"
    Write-HermuseLog "downloading $Label"
    Invoke-WebRequest -Uri $Url -OutFile $partial -MaximumRetryCount 3 -RetryIntervalSec 5
    Move-Item -Force -LiteralPath $partial -Destination $Destination
  }
  Assert-Sha256 $Destination $Sha256 $Label
  return $Destination
}

# Versions from apps/hermuse_app/pubspec.yaml (`X.Y.Z+B` or `X.Y.Z-rc.N+B`,
# the only forms tool/release/release-metadata.sh accepts too).
function Get-HermuseVersions {
  $pubspec = Join-Path $HermuseRepo 'apps/hermuse_app/pubspec.yaml'
  $line = Select-String -LiteralPath $pubspec -Pattern '^version:\s*(\S+)\s*$' | Select-Object -First 1
  if (-not $line) { Stop-Hermuse "no version in $pubspec" }
  $raw = $line.Matches[0].Groups[1].Value.Trim('"', "'")
  if ($raw -notmatch '^(\d+)\.(\d+)\.(\d+)(-(rc\.\d+))?\+(\d+)$') {
    Stop-Hermuse "pubspec version '$raw' is not X.Y.Z+B or X.Y.Z-rc.N+B"
  }
  $core = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
  $version = if ($Matches[5]) { "$core-$($Matches[5])" } else { $core }
  return [pscustomobject]@{
    Pubspec = $raw
    App = $version
    Build = $Matches[6]
    # Numeric four-part version of the Setup.exe resources.
    File = "$core.$($Matches[6])"
    SetupName = "Hermuse-Agent-$version-windows-x64-Setup.exe"
  }
}

# Machine field of a PE file's COFF header (0x8664 = x64), or $null when
# the file is not a PE image.
function Get-PeMachine([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  try {
    $reader = [IO.BinaryReader]::new($stream)
    if ($stream.Length -lt 0x40 -or $reader.ReadUInt16() -ne 0x5A4D) { return $null }
    $stream.Position = 0x3C
    $offset = $reader.ReadInt32()
    if ($offset -lt 0 -or $offset + 6 -gt $stream.Length) { return $null }
    $stream.Position = $offset
    if ($reader.ReadUInt32() -ne 0x00004550) { return $null }
    return [int]$reader.ReadUInt16()
  } finally {
    $stream.Dispose()
  }
}

# Every PE file (.exe/.dll) below $Directory.
function Get-PeFiles([string]$Directory) {
  return @(Get-ChildItem -LiteralPath $Directory -Recurse -File |
      Where-Object { $_.Extension -in '.exe', '.dll' } |
      Sort-Object FullName)
}

# The Visual Studio installation Flutter builds with (vswhere -latest with
# the C++ x64 tools), as {Path, Dumpbin, CrtDir, RedistVersion}.
function Get-VisualStudio {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere)) { Stop-Hermuse "vswhere.exe not found: $vswhere" }
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($LASTEXITCODE -ne 0 -or -not $vs) { Stop-Hermuse 'no Visual Studio with the C++ x64 tools' }
  $vs = @($vs)[0]
  $tools = (Get-Content -LiteralPath (Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt') -Raw).Trim()
  $redist = (Get-Content -LiteralPath (Join-Path $vs 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt') -Raw).Trim()
  $dumpbin = Join-Path $vs "VC/Tools/MSVC/$tools/bin/Hostx64/x64/dumpbin.exe"
  if (-not (Test-Path -LiteralPath $dumpbin)) { Stop-Hermuse "dumpbin.exe not found: $dumpbin" }
  $crt = @(Get-ChildItem -LiteralPath (Join-Path $vs "VC/Redist/MSVC/$redist/x64") -Directory -Filter 'Microsoft.VC*.CRT')
  if ($crt.Count -ne 1) { Stop-Hermuse "expected one x64 Microsoft.VC*.CRT directory in VC redist $redist" }
  return [pscustomobject]@{ Path = $vs; Dumpbin = $dumpbin; CrtDir = $crt[0].FullName; RedistVersion = $redist }
}

# Windows SDK signtool.exe (x64), at least the 10.0.22621.755 the Artifact
# Signing dlib requires.
function Find-SignTool {
  $root = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
  $candidates = @(Get-ChildItem -LiteralPath $root -Directory -Filter '10.*' -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
      Where-Object { Test-Path -LiteralPath $_ } |
      Sort-Object { [version](Get-Item -LiteralPath $_).VersionInfo.FileVersionRaw } -Descending)
  if ($candidates.Count -eq 0) { Stop-Hermuse "no Windows SDK signtool.exe under $root" }
  $signtool = $candidates[0]
  $version = (Get-Item -LiteralPath $signtool).VersionInfo.FileVersionRaw
  if ($version -lt [version]'10.0.22621.755') {
    Stop-Hermuse "signtool $version at $signtool is older than 10.0.22621.755"
  }
  return $signtool
}
