#Requires -Version 7.2
<#
.SYNOPSIS
Hermuse Agent Windows release: one Flutter build, one per-user Setup.exe.

.DESCRIPTION
  pwsh -NoProfile -File packaging/windows/build-release.ps1 [-TestSigning]

Runs on Windows x64 with the Flutter of tool/release/toolchain.lock.json on
PATH, Visual Studio with the C++ x64 tools, the pinned Inno Setup and network
access. Builds in the checkout (apps/hermuse_app/build is ignored) and writes:
  dist/Hermuse-Agent-<version>-windows-x64-Setup.exe
  dist/windows/VERSION.json     fragment merged by tool/release/assemble-release.sh
  dist/windows/SHA256SUMS.txt   `<sha256>  <file>` for the Setup.exe (LF)
Everything else goes to $env:HERMUSE_RELEASE_WORK_DIR (default
<RUNNER_TEMP or TEMP>/hermuse-windows-release), outside the checkout.

Steps: frozen CLIProxyAPI fetch (archive and binary checked against
cliproxy.lock); cliproxy.exe signed when signing; `flutter build windows
--release` with the SHA-256 of that exact cliproxy.exe; bundle = the build
+ cliproxy.exe next to hermuse_app.exe + the Visual C++ runtime DLLs its PE
files import + licence notices; checks (x64 PE, every import bundled or part
of Windows, no JDK link, plugin assets, the bundled cliproxy.exe hash, the
digest compiled into data/app.so); the remaining unsigned PE files signed;
Inno Setup (Setup.exe and its uninstaller signed through sign.ps1).

Signing: with WINDOWS_SIGNING_ENDPOINT, WINDOWS_SIGNING_ACCOUNT and
WINDOWS_SIGNING_PROFILE set (after azure/login), everything is signed with
Azure Artifact Signing (sign.ps1). Without them the release is unsigned and
VERSION.json says so. -TestSigning signs with a throwaway untrusted
certificate instead: it runs every signing step, and the result still counts
as unsigned.
#>
[CmdletBinding()]
param(
  [switch]$TestSigning
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')

$SignScript = Join-Path $PSScriptRoot 'sign.ps1'
$InnoScript = Join-Path $PSScriptRoot 'hermuse-agent.iss'

# --- host ------------------------------------------------------------------------
if (-not $IsWindows) { Stop-Hermuse 'build-release.ps1 runs on Windows' }
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') { Stop-Hermuse 'the builder must be Windows x64' }
foreach ($tool in 'flutter', 'dart', 'git') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Stop-Hermuse "$tool is not on PATH" }
}
$flutterOutput = (& flutter --version --machine 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0) { Stop-Hermuse 'flutter --version --machine failed' }
$flutter = $flutterOutput.Substring($flutterOutput.IndexOf('{')) | ConvertFrom-Json
if ($flutter.frameworkVersion -ne (Get-LockValue 'flutter.version') -or
  $flutter.frameworkRevision -ne (Get-LockValue 'flutter.commit')) {
  Stop-Hermuse "Flutter on PATH is $($flutter.frameworkVersion) ($($flutter.frameworkRevision)), not $(Get-LockValue 'flutter.version') ($(Get-LockValue 'flutter.commit'))"
}

# The Inno Setup install itself: a package manager shim on PATH (Chocolatey)
# carries no version to check.
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (-not (Test-Path -LiteralPath $iscc)) { $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue)?.Source }
if (-not $iscc) { Stop-Hermuse "Inno Setup's ISCC.exe not found" }
$isccInfo = (Get-Item -LiteralPath $iscc).VersionInfo
$innoVersion = "$($isccInfo.FileMajorPart).$($isccInfo.FileMinorPart).$($isccInfo.FileBuildPart)"
if ($innoVersion -ne (Get-LockValue 'windows.inno_setup.version')) {
  Stop-Hermuse "Inno Setup $innoVersion at $iscc is not the pinned $(Get-LockValue 'windows.inno_setup.version')"
}
$vs = Get-VisualStudio

$signingVariables = @(@($env:WINDOWS_SIGNING_ENDPOINT, $env:WINDOWS_SIGNING_ACCOUNT, $env:WINDOWS_SIGNING_PROFILE) |
    Where-Object { $_ })
if ($signingVariables.Count -notin 0, 3) {
  Stop-Hermuse 'WINDOWS_SIGNING_ENDPOINT, WINDOWS_SIGNING_ACCOUNT and WINDOWS_SIGNING_PROFILE are set together or not at all'
}
if ($env:HERMUSE_TEST_SIGNING_PFX) { Stop-Hermuse 'HERMUSE_TEST_SIGNING_PFX is set by -TestSigning only' }
$signing = if ($signingVariables.Count -eq 3) {
  if ($TestSigning) { Stop-Hermuse '-TestSigning and Artifact Signing are exclusive' }
  'artifact-signing'
} elseif ($TestSigning) { 'test-certificate' } else { 'none' }

# --- work directory -----------------------------------------------------------------
$repo = [IO.Path]::GetFullPath($HermuseRepo)
$work = $env:HERMUSE_RELEASE_WORK_DIR
if (-not $work) { $work = Join-Path ($env:RUNNER_TEMP ?? [IO.Path]::GetTempPath()) 'hermuse-windows-release' }
$work = [IO.Path]::GetFullPath($work)
if ("$work\".StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Hermuse 'HERMUSE_RELEASE_WORK_DIR must be outside the checkout'
}
New-Item -ItemType Directory -Force -Path $work | Out-Null
# Keep only the download cache: every cached file is re-verified on use.
Get-ChildItem -LiteralPath $work -Force | Where-Object Name -ne 'cache' | Remove-Item -Recurse -Force
$env:HERMUSE_TOOLS_CACHE = Join-Path $work 'cache'

function New-TestSigningCertificate([string]$Directory) {
  $rsa = [Security.Cryptography.RSA]::Create(3072)
  try {
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
      'CN=Hermuse Agent test signing (untrusted)', $rsa,
      [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $usages = [Security.Cryptography.OidCollection]::new()
    [void]$usages.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
    $request.CertificateExtensions.Add(
      [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($usages, $true))
    $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
        [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
    $now = [DateTimeOffset]::UtcNow
    $certificate = $request.CreateSelfSigned($now.AddMinutes(-5), $now.AddDays(1))
    $password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $pfx = Join-Path $Directory 'test-signing.pfx'
    [IO.File]::WriteAllBytes($pfx, $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password))
    $env:HERMUSE_TEST_SIGNING_PFX = $pfx
    $env:HERMUSE_TEST_SIGNING_PASSWORD = $password
    return $certificate.Thumbprint
  } finally {
    $rsa.Dispose()
  }
}

# Signs $Files with sign.ps1 (same environment, same process).
function Invoke-Sign([string[]]$Files) {
  if ($Files.Count -gt 0) { & $SignScript @Files }
}

# Checks the signature of $File against the signer of this build.
function Assert-Signature([string]$File) {
  $signature = Get-AuthenticodeSignature -LiteralPath $File
  $ok = if ($signing -eq 'test-certificate') {
    $null -ne $signature.SignerCertificate -and $signature.SignerCertificate.Thumbprint -eq $testThumbprint
  } else {
    $signature.Status -eq 'Valid'
  }
  if (-not $ok -or $null -eq $signature.TimeStamperCertificate) {
    Stop-Hermuse "$File is not signed as expected ($($signature.Status))"
  }
}

$testThumbprint = $null
try {
  if ($signing -eq 'test-certificate') {
    $testThumbprint = New-TestSigningCertificate $work
    Write-HermuseLog "test signing certificate $testThumbprint (untrusted)"
  }

  # --- sources ----------------------------------------------------------------------
  $commit = (& git -C $repo rev-parse HEAD)
  if ($LASTEXITCODE -ne 0) { Stop-Hermuse 'git rev-parse HEAD failed' }
  $status = & git -C $repo status --porcelain
  if ($LASTEXITCODE -ne 0) { Stop-Hermuse 'git status failed' }
  $dirty = [bool]$status
  $versions = Get-HermuseVersions
  Write-HermuseLog "Hermuse Agent $($versions.Pubspec) from $commit (dirty: $dirty), signing: $signing"

  # --- CLIProxyAPI ------------------------------------------------------------------
  Push-Location $repo
  try { Invoke-Native flutter @('pub', 'get', '--enforce-lockfile') } finally { Pop-Location }

  $hostPackage = Join-Path $repo 'packages/hermuse_host'
  $cliproxyLock = Join-Path $hostPackage 'cliproxy.lock'
  $lock = Get-Content -Raw -LiteralPath $cliproxyLock | ConvertFrom-Json
  $entry = $lock.platforms.$HermuseCliproxyPlatform
  Write-HermuseLog 'fetching CLIProxyAPI (frozen lockfile)'
  Push-Location $hostPackage
  try {
    $fetchOutput = @(& dart run tool/fetch_cliproxy.dart --platform $HermuseCliproxyPlatform --frozen-lockfile)
    if ($LASTEXITCODE -ne 0) { Stop-Hermuse 'fetch_cliproxy.dart --frozen-lockfile failed' }
  } finally {
    Pop-Location
  }
  $fetched = [IO.Path]::GetFullPath((Join-Path $hostPackage "build/cliproxy/$HermuseCliproxyPlatform/$($entry.binary)"))
  Assert-Sha256 $fetched $entry.binary_sha256 'CLIProxyAPI binary'
  $reported = @($fetchOutput | Where-Object { $_ -match '^([0-9a-f]{64})  (.+)$' } | ForEach-Object {
      [pscustomobject]@{ Sha256 = $Matches[1]; Path = [IO.Path]::GetFullPath($Matches[2]) }
    })
  if ($reported.Count -ne 1 -or $reported[0].Sha256 -ne $entry.binary_sha256 -or $reported[0].Path -ne $fetched) {
    Stop-Hermuse "fetch_cliproxy.dart did not report $fetched with $($entry.binary_sha256)"
  }
  & git -C $repo diff --quiet -- packages/hermuse_host/cliproxy.lock
  if ($LASTEXITCODE -ne 0) { Stop-Hermuse 'cliproxy.lock changed during the fetch' }
  $cliproxyArchive = Join-Path $hostPackage "build/cliproxy/$HermuseCliproxyPlatform/$($entry.asset)"
  Assert-Sha256 $cliproxyArchive $entry.archive_sha256 'CLIProxyAPI archive'

  # The app is compiled with the digest of the exact cliproxy.exe it ships:
  # signing changes the bytes, so it happens first.
  $cliproxy = Join-Path $work "cliproxy/$HermuseBundleCliproxy"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cliproxy) | Out-Null
  Copy-Item -LiteralPath $fetched -Destination $cliproxy
  if ($signing -ne 'none') { Invoke-Sign @($cliproxy) }
  $cliproxySha = Get-Sha256 $cliproxy
  Write-HermuseLog "cliproxy.exe $cliproxySha (upstream $($entry.binary_sha256))"

  # --- build --------------------------------------------------------------------------
  # No JDK for CMake: FindJNI would link the jni plugin's dartjni.dll to jvm.dll.
  Get-ChildItem Env: | Where-Object Name -like 'JAVA_HOME*' | ForEach-Object { Remove-Item "Env:$($_.Name)" }
  $env:Path = (@($env:Path -split ';' | Where-Object {
        $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'java.exe') -PathType Leaf)
      })) -join ';'
  $app = Join-Path $repo 'apps/hermuse_app'
  $release = Join-Path $app 'build/windows/x64/runner/Release'
  # CMake installs the whole bundle there on every build; nothing stale stays.
  Remove-Item -Recurse -Force -LiteralPath $release -ErrorAction SilentlyContinue
  Write-HermuseLog 'flutter build windows --release'
  Push-Location $app
  try {
    Invoke-Native flutter @('build', 'windows', '--release', '--no-pub',
      "--dart-define=HERMUSE_CLIPROXY_SHA256=$cliproxySha",
      "--dart-define=HERMUSE_CLIPROXY_PLATFORM=$HermuseCliproxyPlatform")
  } finally {
    Pop-Location
  }

  # --- bundle -------------------------------------------------------------------------
  $bundle = Join-Path $work 'bundle'
  Copy-Item -LiteralPath $release -Destination $bundle -Recurse
  if (Test-Path -LiteralPath (Join-Path $bundle $HermuseBundleCliproxy)) {
    Stop-Hermuse "the Flutter bundle already has $HermuseBundleCliproxy"
  }
  if (Test-Path -LiteralPath (Join-Path $bundle 'dartjni.dll')) {
    Stop-Hermuse 'the build produced dartjni.dll: CMake found a JDK for the jni plugin'
  }
  Copy-Item -LiteralPath $cliproxy -Destination (Join-Path $bundle $HermuseBundleCliproxy)
  foreach ($required in $HermuseBinary, 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat',
    'data/flutter_assets/NOTICES.Z') {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $required) -PathType Leaf)) {
      Stop-Hermuse "the bundle has no $required (not a release build?)"
    }
  }

  # Every import of every PE file resolves on a Windows without the Visual C++
  # redistributable: the runtime DLLs it needs come from Visual Studio's
  # redist folder next to the executable (app-local deployment).
  $vcRuntime = '^(msvcp\d+(_\w+)?|vcruntime\d+(_\d+)?|concrt\d+|vccorlib\d+|vcomp\d+|vcamp\d+|mfc\d+\w*)\.dll$'
  $debugRuntime = '^(ucrtbased|vcruntime\d+(_\d+)?d|msvcp\d+(_\w+)?d)\.dll$'
  $runtimeFiles = [Collections.Generic.List[string]]::new()
  $systemImports = [Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $queue = [Collections.Generic.Queue[string]]::new()
  Get-PeFiles $bundle | ForEach-Object { $queue.Enqueue($_.FullName) }
  while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    if ((Get-PeMachine $file) -ne 0x8664) { Stop-Hermuse "$file is not an x64 PE image" }
    $dump = & $vs.Dumpbin /nologo /dependents $file
    if ($LASTEXITCODE -ne 0) { Stop-Hermuse "dumpbin /dependents $file failed" }
    $listing = $false
    foreach ($line in $dump) {
      if ($line -match 'has the following (delay load )?dependencies') { $listing = $true; continue }
      if ($line -match '^\s*Summary\s*$') { break }
      if (-not $listing -or $line -notmatch '^\s+(\S+\.dll)\s*$') { continue }
      $import = $Matches[1]
      if (Test-Path -LiteralPath (Join-Path $bundle $import)) { continue }
      if ($import -eq 'jvm.dll') { Stop-Hermuse "$file links jvm.dll: a JDK leaked into the build" }
      if ($import -match $debugRuntime) { Stop-Hermuse "$file links the debug runtime $import" }
      if ($import -match $vcRuntime) {
        $source = Join-Path $vs.CrtDir $import
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
          Stop-Hermuse "$file needs $import, absent from the Visual C++ $($vs.RedistVersion) redistributable"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $bundle $import)
        $runtimeFiles.Add($import)
        $queue.Enqueue((Join-Path $bundle $import))
        continue
      }
      if ($import -match '^(api|ext)-ms-win-' -or
        (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32/$import") -PathType Leaf)) {
        [void]$systemImports.Add($import)
        continue
      }
      Stop-Hermuse "$file needs $import, which is neither bundled nor part of Windows"
    }
  }
  Write-HermuseLog "Visual C++ runtime $($vs.RedistVersion): $($runtimeFiles -join ', ')"
  Write-HermuseLog "Windows imports: $($systemImports -join ', ')"

  $pluginVersion = (Select-String -LiteralPath (Join-Path $repo 'hermes-plugin/hermuse/plugin.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value.Trim('"', "'")
  $bundledPlugin = Join-Path $bundle 'data/flutter_assets/assets/hermes-plugin/hermuse/plugin.yaml'
  if (-not (Test-Path -LiteralPath $bundledPlugin)) { Stop-Hermuse 'the bundle has no Hermes plugin assets' }
  $bundledPluginVersion = (Select-String -LiteralPath $bundledPlugin -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value.Trim('"', "'")
  if ($bundledPluginVersion -ne $pluginVersion) {
    Stop-Hermuse "bundled plugin assets are $bundledPluginVersion, not hermes-plugin/hermuse $pluginVersion (run tool/sync_plugin_assets.dart)"
  }
  $hermesCommit = (Select-String -LiteralPath (Join-Path $hostPackage 'lib/src/installer.dart') `
      -Pattern '^const hermesReleaseCommit = ''([0-9a-f]{40})'';$').Matches[0].Groups[1].Value
  if (-not $hermesCommit) { Stop-Hermuse 'no hermesReleaseCommit in installer.dart' }

  # CliproxyBinary.locate accepts only the digest compiled into the snapshot.
  $snapshot = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes((Join-Path $bundle 'data/app.so')))
  if (-not $snapshot.Contains($cliproxySha) -or -not $snapshot.Contains($HermuseCliproxyPlatform)) {
    Stop-Hermuse "data/app.so does not carry HERMUSE_CLIPROXY_SHA256=$cliproxySha"
  }

  $notices = Join-Path $bundle 'notices'
  New-Item -ItemType Directory -Path $notices | Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination (Join-Path $notices 'hermuse-agent-AGPL-3.0.txt')
  Copy-Item -LiteralPath (Join-Path $repo 'packages/yellow_stick_ui/fonts/OFL.txt') -Destination (Join-Path $notices 'inter-OFL-1.1.txt')
  foreach ($notice in 'lucide-ISC.txt', 'sqlite-public-domain.txt') {
    Copy-Item -LiteralPath (Join-Path $repo "packaging/linux/notices/$notice") -Destination (Join-Path $notices $notice)
  }
  $zip = [IO.Compression.ZipFile]::OpenRead($cliproxyArchive)
  try {
    $license = $zip.Entries | Where-Object FullName -eq 'LICENSE' | Select-Object -First 1
    if (-not $license) { Stop-Hermuse "no LICENSE in $cliproxyArchive" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($license, (Join-Path $notices 'cliproxyapi-MIT.txt'))
  } finally {
    $zip.Dispose()
  }
  $compressed = [IO.File]::OpenRead((Join-Path $bundle 'data/flutter_assets/NOTICES.Z'))
  try {
    $gzip = [IO.Compression.GZipStream]::new($compressed, [IO.Compression.CompressionMode]::Decompress)
    $plain = [IO.File]::Create((Join-Path $notices 'flutter-NOTICES.txt'))
    try { $gzip.CopyTo($plain) } finally { $plain.Dispose(); $gzip.Dispose() }
  } finally {
    $compressed.Dispose()
  }

  # --- signing ----------------------------------------------------------------------
  if ($signing -ne 'none') {
    # The Microsoft-signed runtime DLLs keep their signature.
    $unsigned = @(Get-PeFiles $bundle | Where-Object {
        $_.Name -ne $HermuseBundleCliproxy -and (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid'
      } | ForEach-Object FullName)
    Invoke-Sign $unsigned
    Assert-Signature (Join-Path $bundle $HermuseBundleCliproxy)
  }
  Assert-Sha256 (Join-Path $bundle $HermuseBundleCliproxy) $cliproxySha "bundled $HermuseBundleCliproxy"

  # --- installer ----------------------------------------------------------------------
  $out = Join-Path $work 'out'
  $setupBase = [IO.Path]::GetFileNameWithoutExtension($versions.SetupName)
  $isccArguments = @(
    "/DAppVersion=$($versions.App)",
    "/DFileVersion=$($versions.File)",
    "/DBundleDir=$([IO.Path]::GetFullPath($bundle))",
    "/DIconFile=$([IO.Path]::GetFullPath($HermuseIcon))",
    "/DOutputDir=$([IO.Path]::GetFullPath($out))",
    "/DOutputBaseFilename=$setupBase")
  if ($signing -ne 'none') {
    # ISCC runs this for the uninstaller and Setup.exe ($q: quote, $f: file).
    $pwsh = (Get-Process -Id $PID).Path
    $isccArguments += '/DSign'
    $isccArguments += '/Shermuse=$q' + $pwsh + '$q -NoProfile -NonInteractive -File $q' +
    [IO.Path]::GetFullPath($SignScript) + '$q $f'
  }
  $isccArguments += [IO.Path]::GetFullPath($InnoScript)
  Write-HermuseLog "Inno Setup $innoVersion"
  Invoke-Native $iscc $isccArguments
  $setup = Join-Path $out $versions.SetupName
  if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { Stop-Hermuse "ISCC did not write $setup" }
  if ($signing -ne 'none') { Assert-Signature $setup }

  # --- dist ---------------------------------------------------------------------------
  $dist = Join-Path $repo 'dist'
  $fragment = Join-Path $dist 'windows'
  Remove-Item -Recurse -Force -LiteralPath $fragment -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $dist -Filter 'Hermuse-Agent-*-windows-x64-Setup.exe' -ErrorAction SilentlyContinue |
    Remove-Item -Force
  New-Item -ItemType Directory -Force -Path $fragment | Out-Null
  $distSetup = Join-Path $dist $versions.SetupName
  Copy-Item -LiteralPath $setup -Destination $distSetup
  $setupSha = Get-Sha256 $distSetup
  $reason = switch ($signing) {
    'artifact-signing' { $null }
    'test-certificate' { 'signed with an untrusted test certificate (-TestSigning), not for release' }
    default { 'WINDOWS_SIGNING_ENDPOINT, WINDOWS_SIGNING_ACCOUNT and WINDOWS_SIGNING_PROFILE are not set' }
  }
  $client = if ($signing -eq 'artifact-signing') {
    [ordered]@{
      package = Get-LockValue 'windows.artifact_signing_client.package'
      version = Get-LockValue 'windows.artifact_signing_client.version'
    }
  } else { $null }
  $version = [ordered]@{
    schema = 1
    os = 'windows'
    arch = 'x64'
    app = [ordered]@{
      name = $HermuseAppName; id = $HermuseAppId; version = $versions.App; build = $versions.Build
      pubspec_version = $versions.Pubspec; installer_app_id = $HermuseInstallerAppId
    }
    source = [ordered]@{ commit = $commit; dirty = $dirty }
    plugin = [ordered]@{ name = 'hermuse'; version = $pluginVersion }
    hermes = [ordered]@{ commit = $hermesCommit }
    cliproxy = [ordered]@{
      version = $lock.version; platform = $HermuseCliproxyPlatform; binary_sha256 = $cliproxySha
      upstream_binary_sha256 = $entry.binary_sha256; archive_sha256 = $entry.archive_sha256
      path = $HermuseBundleCliproxy
    }
    signing = [ordered]@{ signed = $signing -eq 'artifact-signing'; method = $signing; reason = $reason }
    toolchain = [ordered]@{
      flutter = [ordered]@{ version = $flutter.frameworkVersion; commit = $flutter.frameworkRevision }
      inno_setup = [ordered]@{ version = $innoVersion }
      vc_runtime = [ordered]@{ version = $vs.RedistVersion; files = @($runtimeFiles) }
      signing_client = $client
    }
    install = [ordered]@{
      scope = 'per-user'
      directory = '%LOCALAPPDATA%\Programs\Hermuse Agent'
      executable = $HermuseBinary
      start_menu_shortcut = '%APPDATA%\Microsoft\Windows\Start Menu\Programs\Hermuse Agent.lnk'
      uninstaller = 'unins000.exe'
      app_data = '%APPDATA%\Yellow Stick\Hermuse Agent'
      hermes_home = '%LOCALAPPDATA%\hermes'
    }
    artifacts = @([ordered]@{ name = $versions.SetupName; sha256 = $setupSha; size = (Get-Item -LiteralPath $distSetup).Length })
  }
  $utf8 = [Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllText((Join-Path $fragment 'VERSION.json'),
    ($version | ConvertTo-Json -Depth 8).Replace("`r`n", "`n") + "`n", $utf8)
  [IO.File]::WriteAllText((Join-Path $fragment 'SHA256SUMS.txt'), "$setupSha  $($versions.SetupName)`n", $utf8)
  Write-HermuseLog "release artifacts in ${dist}:"
  Get-Item -LiteralPath $distSetup, (Join-Path $fragment 'VERSION.json'), (Join-Path $fragment 'SHA256SUMS.txt') |
    Format-Table -AutoSize Length, FullName | Out-Host
  Get-Content -LiteralPath (Join-Path $fragment 'SHA256SUMS.txt') | Out-Host
} finally {
  if ($env:HERMUSE_TEST_SIGNING_PFX) {
    Remove-Item -Force -LiteralPath $env:HERMUSE_TEST_SIGNING_PFX -ErrorAction SilentlyContinue
    Remove-Item Env:HERMUSE_TEST_SIGNING_PFX, Env:HERMUSE_TEST_SIGNING_PASSWORD -ErrorAction SilentlyContinue
  }
}
