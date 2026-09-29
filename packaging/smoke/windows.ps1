<#
.SYNOPSIS
Scenario runner of the Hermuse Agent Windows release smoke.

.DESCRIPTION
Runs on the GitHub-hosted Windows Server 2025 runner itself, in the
interactive desktop session of its user: the VM is new for every job and has
no nested virtualization for a guest, so no Docker either. It exercises the
PACKAGED artifact the way a user does: Setup.exe installed silently for the
current user, the app started through its Start menu shortcut with a new
user's default PATH (the runner's tool directories stay out of its reach),
a real window, real buttons (OCR + SendInput pointer events, see
desktop/desktop.py), the real DPAPI secret store, the real Hermes install at
the pin (install.ps1), the bundled plugin and bridge, then an uninstall that
keeps the user's data. Every acceptance criterion gets results/<id>.json, as
linux.sh writes them:

  {schema, id, criterion, guest, format, scenario, run, status, checks[],
   gui_proof[]}      status: pass | fail | manual-gate | skipped-missing-prereq

A manual gate is never a pass: its screenshots (gui_proof) wait for the
release approver. The agent's computer needs Docker, which the hosted runner
cannot run: criterion 7 is a manual gate with the app's own report.

.EXAMPLE
pwsh -NoProfile -File packaging/smoke/windows.ps1 -Scenario fresh -Dist dist -Out out -RunId 1-1 -Runner windows-2025
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('fresh')][string]$Scenario,
  # Holds the Setup.exe and windows/VERSION.json (packaging/windows/build-release.ps1).
  [Parameter(Mandatory)][string]$Dist,
  [Parameter(Mandatory)][string]$Out,
  [Parameter(Mandatory)][string]$RunId,
  [Parameter(Mandatory)][string]$Runner,
  [ValidateRange(1, 10)][int]$TimeoutScale = 1
)
# Version 1: uninitialized variables are errors; a JSON property a probe did
# not return reads as $null (the verdicts check it).
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# --- configuration ------------------------------------------------------------

$AppName = 'Hermuse Agent'
$WindowTitle = 'Hermuse Agent'
$InnoAppId = '{623CBA2D-B2D8-40B4-B0A3-334510D03899}'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Hermuse Agent'
$AppExe = Join-Path $InstallDir 'hermuse_app.exe'
$StartMenuLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Hermuse Agent.lnk'
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${InnoAppId}_is1"
$AppData = Join-Path $env:APPDATA 'Yellow Stick\Hermuse Agent'
$SecretFile = Join-Path $AppData 'flutter_secure_storage.dat'
# The app's default when HERMES_HOME is unset (a new user never has it).
$HermesHome = Join-Path $env:LOCALAPPDATA 'hermes'
$LocalSecrets = 'hermes/hermuse-local/'
# A new Windows user's PATH: what Explorer gives the app on a machine without
# the runner image's tools (Git, Python, Node, ...).
$UserPath = @(
  "$env:SystemRoot\system32", $env:SystemRoot, "$env:SystemRoot\System32\Wbem",
  "$env:SystemRoot\System32\WindowsPowerShell\v1.0\", "$env:SystemRoot\System32\OpenSSH\",
  (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
) -join ';'

# UI copy the automation reads and clicks (OCR). It MUST equal the app's
# English labels: a missing core label fails the flow, a missing secondary one
# turns that GUI proof into a manual gate.
$UiConnectTitle = 'Connect to a Hermes'
$UiLocalChoice = 'Install Hermes on this computer'
$UiKeystoreError = 'Secure storage unavailable'
$UiRetryStage = 'Retry this stage'
$UiEnablePlugin = 'Enable the Hermuse plugin'
$UiInstallPlugin = 'Install the plugin'
$UiBackToChat = 'Back to chat'
$UiConnections = 'Connections'
$UiSearchConnections = 'Search connections'
$UiBridgeCard = 'Meta (bridge)'
$UiConnect = 'Connect'
$UiCancel = 'Cancel'
$UiFeed = 'Feed'
$UiGoals = 'Goals'
$UiDockerNotice = 'Install Docker'

# --- setup ----------------------------------------------------------------------

$Dist = (Resolve-Path $Dist).Path
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$Res = Join-Path $Out 'results'
$Evid = Join-Path $Out 'evidence'
$Logs = Join-Path $Evid 'logs'
$Probe = Join-Path $Evid 'probe'
$Shots = Join-Path $Evid 'screens'
foreach ($dir in $Res, $Logs, $Probe, $Shots) { New-Item -ItemType Directory -Force $dir | Out-Null }
Set-Content -Path (Join-Path $Out 'checks.jsonl') -Value $null -NoNewline

$VersionJson = Join-Path $Dist 'windows\VERSION.json'
if (-not (Test-Path $VersionJson)) { throw "$Dist must contain windows\VERSION.json" }
$Version = Get-Content $VersionJson -Raw | ConvertFrom-Json
$AppVersion = $Version.app.version
$PinCommit = $Version.hermes.commit
$Setup = Join-Path $Dist (@($Version.artifacts | Where-Object { $_.name -like '*-Setup.exe' })[0].name)
$Signed = [bool]$Version.signing.signed

$Python = (Get-Command python -ErrorAction Stop).Source
$Helper = Join-Path $PSScriptRoot 'desktop\desktop.py'
$Expected = [System.Collections.Generic.List[string]]::new()
$Started = [Diagnostics.Stopwatch]::StartNew()
$Recorder = $null

function Log([string]$Message) { Write-Host ("[{0:HH:mm:ss}] {1}" -f [DateTime]::UtcNow, $Message) }
function T([int]$Seconds) { $Seconds * $TimeoutScale }
function D { & $Python $Helper @args }
function Stamp { Get-Date -Format 'HHmmss' }

function Wait-Until([int]$TimeoutSec, [int]$IntervalSec, [scriptblock]$Predicate) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
  while ($true) {
    if (& $Predicate) { return $true }
    if ([DateTime]::UtcNow -ge $deadline) { return $false }
    Start-Sleep -Seconds $IntervalSec
  }
}

# --- results ---------------------------------------------------------------------

function Get-Criterion([string]$Id) {
  if ($Id -eq 'c0-test-base') { return 'base' }
  if ($Id -match '^c(\d+)-') { return $Matches[1] }
  return '?'
}

function Add-Check([string]$Id, [string]$Name, [string]$Status, [string]$Detail, [string[]]$Evidence = @()) {
  $paths = @($Evidence | Where-Object { $_ })
  D result check $Out $Id (Get-Criterion $Id) $Name $Status $Detail @paths 2>&1 | ForEach-Object { Write-Host $_ }
}

function Add-Verdict([string]$Id, [string]$Name, [bool]$Ok, [string]$Detail, [string[]]$Evidence = @()) {
  Add-Check $Id $Name $(if ($Ok) { 'pass' } else { 'fail' }) $Detail $Evidence
}

function Complete-Results([int]$ExitCode) {
  $expects = foreach ($id in $Expected) { '--expect'; "$id=$(Get-Criterion $id)" }
  D result finalize $Out --runner $Runner --format setup --scenario $Scenario --run $RunId --exit-code $ExitCode @expects
}

# --- app and GUI ------------------------------------------------------------------

function Get-AppProcess { @(Get-Process -Name hermuse_app -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $AppExe }) }
function Test-AppGone { (Get-AppProcess).Count -eq 0 }
function Save-Shot([string]$Name) { (D shot (Join-Path $Shots "$(Stamp)-$Name.png")) | Select-Object -Last 1 }

function Invoke-UiClick([string]$Phrase, [int]$TimeoutSec, [string]$Mode = 'line') {
  $png = D click $Phrase --shots $Shots --timeout $TimeoutSec --mode $Mode --window $WindowTitle 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return @($png)[-1]
}

function Wait-UiText([string]$Phrase, [int]$TimeoutSec, [string]$Mode = 'any') {
  $png = D wait-text $Phrase --shots $Shots --timeout $TimeoutSec --mode $Mode 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return @($png)[-1]
}

function Test-BackendUp {
  D backend *> (Join-Path $Probe 'backend.json')
  return $LASTEXITCODE -eq 0
}

function Invoke-Rest([string]$Method, [string]$Path, [string]$File) {
  D rest $Method $Path *> $File
  return $LASTEXITCODE -eq 0
}

function Read-Json([string]$File) {
  try { return Get-Content $File -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

# Starts the app through its Start menu shortcut (ShellExecute, as the Start
# menu does) with a new user's PATH and without the runner's own variables
# (CI, GITHUB_*, RUNNER_*: a user session has none), and waits for its
# window, then maximized.
function Start-App([string]$Label) {
  $saved = @{}
  foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -match '^(CI|GITHUB_.*|RUNNER_.*|ACTIONS_.*|ImageOS|ImageVersion)$' } |
      ForEach-Object Name) + 'Path') {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
  }
  try {
    $env:Path = $UserPath
    Start-Process -FilePath $StartMenuLink -WorkingDirectory (New-Item -ItemType Directory -Force (Join-Path $env:TEMP "hermuse-cwd-$Label")).FullName
  } finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  }
  D window $WindowTitle --timeout (T 180) *> (Join-Path $Logs "window-$Label.txt")
  if ($LASTEXITCODE -ne 0) { return $false }
  D maximize $WindowTitle | Out-Null
  Start-Sleep -Seconds 3
  Log "app running: pid $((Get-AppProcess).Id -join ','), window $(Get-Content (Join-Path $Logs "window-$Label.txt") -Raw)"
  return $true
}

# WM_CLOSE, as the titlebar button sends it: the app stops the processes it supervises.
function Stop-App([int]$TimeoutSec = (T 300)) {
  if (Test-AppGone) { return $true }
  D close $WindowTitle | Out-Null
  return Wait-Until $TimeoutSec 2 { Test-AppGone }
}

# A transient failure the app reports with its retry button (e.g. HTTP 429 of
# raw.githubusercontent.com): a user reads the error and clicks the button.
# The screen is read at most every minute, the button clicked at most every 3
# minutes; each click is kept as evidence.
$script:RetryLooked = -1000
$script:RetryClicked = -1000
function Invoke-RetryWhenOffered([string]$Id) {
  $now = [int]$Started.Elapsed.TotalSeconds
  if ($now - $script:RetryLooked -lt 60 -or $now - $script:RetryClicked -lt 180) { return }
  $script:RetryLooked = $now
  $png = Save-Shot 'retry-offered'
  if (-not $png) { return }
  $text = (D text $png) -join "`n"
  if ($text -match '(?i)\b(cannot|failed|error|unable)\b') {
    $xy = D locate $png $UiRetryStage
    if ($LASTEXITCODE -eq 0 -and $xy) {
      $parts = "$xy".Trim() -split ' '
      D pointer $parts[0] $parts[1]
      $script:RetryClicked = $now
      Add-Check $Id 'user-retry' 'pass' "the app reported an error with '$UiRetryStage': clicked it, as a user does" @($png)
      return
    }
  }
  Remove-Item $png -ErrorAction SilentlyContinue
}

function Test-ReadyOrRetry([string]$Id, [scriptblock]$Predicate) {
  if (& $Predicate) { return $true }
  Invoke-RetryWhenOffered $Id
  return $false
}

function Get-TreeManifest([string]$Root) {
  # Relative path, size and last write of every file: what an uninstall must
  # not change (hashing a Hermes checkout and its venvs would take minutes).
  if (-not (Test-Path $Root)) { return @() }
  $prefix = (Resolve-Path $Root).Path.Length + 1
  Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object { '{0} {1} {2:o}' -f $_.FullName.Substring($prefix), $_.Length, $_.LastWriteTimeUtc } |
    Sort-Object
}

# --- criterion checks ------------------------------------------------------------

function Test-Base {
  $id = 'c0-test-base'
  $os = Get-CimInstance Win32_OperatingSystem
  $os | Format-List Caption, Version, BuildNumber, OSArchitecture | Out-File (Join-Path $Logs 'os.txt')
  Add-Check $id 'os' 'pass' "$($os.Caption) $($os.Version) ($($os.OSArchitecture)), runner $Runner" @((Join-Path $Logs 'os.txt'))
  Add-Verdict $id 'x64' ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') 'x64 (the only Windows target)'
  $tesseract = (Get-Command tesseract -ErrorAction SilentlyContinue).Source
  if (-not $tesseract) { $tesseract = "$env:ProgramFiles\Tesseract-OCR\tesseract.exe" }
  & {
    & $Python --version
    & $tesseract --version 2>&1 | Select-Object -First 1
    magick -version | Select-Object -First 1
    "session $((Get-Process -Id $PID).SessionId), user $env:USERNAME"
  } *> (Join-Path $Logs 'tools.txt')
  # What the app installs itself: none of it may pre-exist on the runner.
  $present = @(foreach ($path in $HermesHome, $InstallDir, $AppData, $StartMenuLink, $UninstallKey) {
      if (Test-Path $path) { $path }
    })
  $userHermes = [Environment]::GetEnvironmentVariable('HERMES_HOME', 'User')
  if ($userHermes) { $present += "user HERMES_HOME=$userHermes" }
  $present | Out-File (Join-Path $Logs 'prior-state.txt')
  Add-Verdict $id 'no-prior-state' ($present.Count -eq 0) `
    "no Hermes, HERMES_HOME, app, app data or shortcut before the test$(if ($present) { '; found: ' + ($present -join ', ') })" `
    @((Join-Path $Logs 'prior-state.txt'))
  $extras = @(foreach ($tool in 'git', 'node', 'uv', 'docker') { if (Get-Command $tool -ErrorAction SilentlyContinue) { $tool } })
  Add-Check $id 'runner-image' 'pass' `
    "hosted image tools on the runner PATH: $($extras -join ', ') (the app starts with a new user's PATH, without them)" `
    @((Join-Path $Logs 'tools.txt'))
}

function Test-Launch {
  $id = 'c1-launch'
  $signature = Get-AuthenticodeSignature -FilePath $Setup
  $signature | Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate |
    Out-File (Join-Path $Logs 'setup-signature.txt')
  if ($Signed) {
    Add-Verdict $id 'authenticode' ($signature.Status -eq 'Valid' -and $signature.TimeStamperCertificate) `
      "Setup.exe Authenticode: $($signature.Status), signer $($signature.SignerCertificate.Subject), timestamped" `
      @((Join-Path $Logs 'setup-signature.txt'))
  } else {
    Add-Check $id 'authenticode' 'skipped-missing-prereq' `
      "unsigned build ($($Version.signing.reason)): SmartScreen and Authenticode are proven on signed release builds only" `
      @((Join-Path $Logs 'setup-signature.txt'))
  }
  $installLog = Join-Path $Logs 'setup-install.log'
  $proc = Start-Process -FilePath $Setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$installLog`"" `
    -Wait -PassThru
  Add-Verdict $id 'silent-install' ($proc.ExitCode -eq 0 -and (Test-Path $AppExe)) `
    "Setup.exe /VERYSILENT for the current user: exit $($proc.ExitCode), $AppExe present" @($installLog)
  if (-not (Test-Path $AppExe)) { return $false }
  $key = Get-ItemProperty -Path $UninstallKey -ErrorAction SilentlyContinue
  $key | Format-List DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString |
    Out-File (Join-Path $Logs 'uninstall-key.txt')
  Add-Verdict $id 'per-user' ($null -ne $key -and $key.DisplayName -eq $AppName -and $key.Publisher -eq 'Yellow Stick' `
      -and $key.DisplayVersion -like "$AppVersion*" -and -not (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${InnoAppId}_is1")) `
    "per-user install under %LOCALAPPDATA%\Programs, HKCU uninstall entry '$AppName' by Yellow Stick, version $AppVersion" `
    @((Join-Path $Logs 'uninstall-key.txt'))
  Get-ChildItem -LiteralPath $InstallDir -Recurse -File | ForEach-Object { $_.FullName.Substring($InstallDir.Length + 1) } |
    Out-File (Join-Path $Logs 'installed-files.txt')
  $cliproxy = Join-Path $InstallDir 'cliproxy.exe'
  $got = if (Test-Path $cliproxy) { (Get-FileHash -Algorithm SHA256 $cliproxy).Hash.ToLowerInvariant() } else { 'missing' }
  Add-Verdict $id 'bundle-integrity' ($got -eq $Version.cliproxy.binary_sha256) "cliproxy.exe next to the app matches VERSION.json ($got)" `
    @((Join-Path $Logs 'installed-files.txt'))
  $shell = New-Object -ComObject WScript.Shell
  $target = if (Test-Path $StartMenuLink) { $shell.CreateShortcut($StartMenuLink).TargetPath } else { '' }
  Add-Verdict $id 'start-menu' ($target -eq $AppExe) "Start menu shortcut '$AppName' targets $target"
  if (-not (Start-App 'first')) {
    Add-Check $id 'window' 'fail' "no window titled '$WindowTitle' after starting the Start menu shortcut" @((Save-Shot 'no-window'))
    return $false
  }
  $png = Save-Shot 'welcome'
  D text $png *> (Join-Path $Logs 'ocr-welcome.txt')
  $title = (D text $png --title-bar $WindowTitle) -join "`n"
  Set-Content -Path (Join-Path $Logs 'ocr-title-bar.txt') -Value $title
  Add-Verdict $id 'window-title' ($title -match '(?i)hermuse agent') `
    "window '$WindowTitle' (window manager) with 'Hermuse Agent' read by OCR in its title bar" @($png, (Join-Path $Logs 'ocr-title-bar.txt'))
  D locate $png $UiConnectTitle --mode any | Out-Null
  $welcome = $LASTEXITCODE -eq 0
  D locate $png $UiLocalChoice | Out-Null
  $welcome = $welcome -and $LASTEXITCODE -eq 0
  Add-Verdict $id 'welcome' $welcome "Welcome screen: '$UiConnectTitle' and '$UiLocalChoice' (OCR)" @($png, (Join-Path $Logs 'ocr-welcome.txt'))
  $ocr = Get-Content (Join-Path $Logs 'ocr-welcome.txt') -Raw
  Add-Verdict $id 'keystore-probe' (-not ($ocr -match [regex]::Escape($UiKeystoreError))) `
    "the launch round-trip of the secret store passed: no '$UiKeystoreError' screen" @($png)
  Add-Check $id 'taskbar-icon' 'manual-gate' 'confirm the window and taskbar show the Hermuse icon' @($png)
  return $true
}

function Test-Hermes {
  $id = 'c4-hermes'
  $png = Invoke-UiClick $UiLocalChoice (T 60)
  if (-not $png) {
    Add-Check $id 'local-choice' 'fail' "no '$UiLocalChoice' button" @((Save-Shot 'local-choice-missing'))
    return $false
  }
  Add-Check $id 'local-choice' 'pass' "clicked '$UiLocalChoice' (OCR + pointer event)" @($png)
  if (-not (Wait-Until (T 3600) 10 { Test-ReadyOrRetry $id { Test-BackendUp } })) {
    Add-Check $id 'backend-serve' 'fail' 'no app-supervised backend answering /api/status' @((Save-Shot 'install-stuck'), (Join-Path $Probe 'backend.json'))
    return $false
  }
  Save-Shot 'backend-up' | Out-Null
  $journalFile = Join-Path $AppData 'hermes-install.json'
  Copy-Item $journalFile (Join-Path $Logs 'journal.json') -ErrorAction SilentlyContinue
  $journal = Read-Json $journalFile
  $installDir = Join-Path $HermesHome 'hermes-agent'
  $ok = $null -ne $journal -and $journal.commit -eq $PinCommit -and $journal.finished -eq $true -and
    $journal.hermes_home -eq $HermesHome -and $journal.install_dir -eq $installDir -and @($journal.completed_stages).Count -gt 0
  Add-Verdict $id 'journal' $ok "install journal finished, pinned to $PinCommit, stages: $(if ($journal) { @($journal.completed_stages) -join ' ' })" `
    @((Join-Path $Logs 'journal.json'))
  $markerFile = Join-Path $installDir '.hermes-bootstrap-complete'
  Copy-Item $markerFile (Join-Path $Logs 'hermes-bootstrap-complete.json') -ErrorAction SilentlyContinue
  $marker = Read-Json $markerFile
  $head = (& git -C $installDir rev-parse HEAD 2>$null) -join ''
  Add-Verdict $id 'pinned-checkout' ($null -ne $marker -and $marker.pinnedCommit -eq $PinCommit -and $head -eq $PinCommit) `
    "checkout HEAD and bootstrap marker at $PinCommit" @((Join-Path $Logs 'hermes-bootstrap-complete.json'))
  $launcher = @((Join-Path $HermesHome 'bin\hermes.exe'), (Join-Path $HermesHome 'bin\hermes.cmd')) | Where-Object { Test-Path $_ } |
    Select-Object -First 1
  $versionLog = Join-Path $Logs 'hermes-version.txt'
  if ($launcher) {
    & $launcher --version *> $versionLog
    Add-Verdict $id 'launcher-version' ((Get-Content $versionLog -Raw) -match '0\.21\.') `
      "$launcher answers $((Get-Content $versionLog | Select-Object -First 1))" @($versionLog)
  } else {
    Add-Check $id 'launcher-version' 'fail' "no hermes launcher in $HermesHome\bin"
  }
  $backend = Read-Json (Join-Path $Probe 'backend.json')
  $ok = $null -ne $backend -and $backend.backend.hermes_desktop -eq '1' -and $backend.backend.userprofile -eq $env:USERPROFILE -and
    "$($backend.api_status.version)" -match '^0\.21\.' -and (-not $backend.backend.hermes_home -or $backend.backend.hermes_home -eq $HermesHome)
  Add-Verdict $id 'backend-serve' $ok `
    "supervised 'hermes serve' answers /api/status on loopback with the real profile ($(if ($backend) { $backend.api_status.version }))" `
    @((Join-Path $Probe 'backend.json'))
  return $true
}

function Test-Keyring {
  $id = 'c3-keyring'
  D dpapi roundtrip *> (Join-Path $Probe 'dpapi-roundtrip.json')
  Add-Verdict $id 'fixture-secret-roundtrip' ($LASTEXITCODE -eq 0) 'protect and unprotect a fixture secret with DPAPI (CurrentUser)' `
    @((Join-Path $Probe 'dpapi-roundtrip.json'))
  D dpapi decrypt $SecretFile *> (Join-Path $Probe 'secret-store.json')
  $ok = $LASTEXITCODE -eq 0
  $store = Read-Json (Join-Path $Probe 'secret-store.json')
  $local = @(if ($store -and $store.keys) { $store.keys | Where-Object { $_ -like "$LocalSecrets*" } })
  Add-Verdict $id 'app-secrets-dpapi' ($ok -and $local.Count -gt 0) `
    "the app's store is DPAPI-sealed (raw bytes not JSON, no key name in clear) and holds the local instance's secrets: $($local -join ' ')" `
    @((Join-Path $Probe 'secret-store.json'))
  D plaintext $AppData --name $LocalSecrets *> (Join-Path $Probe 'plaintext.json')
  Add-Verdict $id 'no-plaintext' ($LASTEXITCODE -eq 0) `
    "neither the backend's session token nor the app's secret names in the app's files ($AppData)" @((Join-Path $Probe 'plaintext.json'))
}

function Get-CronIds([string]$File) {
  $data = Read-Json $File
  if (-not $data) { return @() }
  @($data.body.jobs | Where-Object { $_.registered } | ForEach-Object { $_.job_id } | Sort-Object)
}

function Compare-Tree([string]$Left, [string]$Right, [string]$Report) {
  $manifest = {
    param($root)
    $prefix = (Resolve-Path $root).Path.Length + 1
    Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\__pycache__\\' } |
      ForEach-Object { '{0} {1}' -f $_.FullName.Substring($prefix), (Get-FileHash -Algorithm SHA256 $_.FullName).Hash } | Sort-Object
  }
  if (-not (Test-Path $Left) -or -not (Test-Path $Right)) { "missing: $Left or $Right" | Out-File $Report; return $false }
  $diff = Compare-Object (& $manifest $Left) (& $manifest $Right)
  $diff | Out-File $Report
  return $null -eq $diff
}

function Test-Plugin {
  $id = 'c5-plugin'
  Invoke-UiClick $UiBackToChat 10 | Out-Null
  D rail 2 $WindowTitle *> (Join-Path $Logs 'rail.txt')
  $png = if ($LASTEXITCODE -eq 0) { Wait-UiText $UiEnablePlugin (T 60) }
  if (-not $png) {
    Add-Check $id 'plugin-gate' 'fail' "Feed does not show '$UiEnablePlugin'" @((Save-Shot 'plugin-gate-missing'), (Join-Path $Logs 'rail.txt'))
    return $false
  }
  Add-Check $id 'plugin-gate' 'pass' "Feed shows '$UiEnablePlugin' for the local instance" @($png)
  $png = Invoke-UiClick $UiInstallPlugin (T 30)
  if (-not $png) {
    Add-Check $id 'plugin-install' 'fail' "no '$UiInstallPlugin' button" @((Save-Shot 'install-plugin-missing'))
    return $false
  }
  $feedJson = Join-Path $Probe 'feed.json'
  if (-not (Wait-Until (T 900) 5 { (Test-Path (Join-Path $HermesHome 'plugins\hermuse\plugin.yaml')) -and (Invoke-Rest GET /api/plugins/hermuse/feed $feedJson) })) {
    Add-Check $id 'plugin-install' 'fail' 'the plugin never served /api/plugins/hermuse/feed' @((Save-Shot 'plugin-stuck'), $feedJson)
    return $false
  }
  Add-Check $id 'plugin-install' 'pass' "clicked '$UiInstallPlugin': the restarted backend serves the plugin" @($png)
  $assets = Join-Path $InstallDir 'data\flutter_assets\assets\hermes-plugin\hermuse'
  Add-Verdict $id 'plugin-copied' (Compare-Tree $assets (Join-Path $HermesHome 'plugins\hermuse') (Join-Path $Logs 'plugin-diff.txt')) `
    "HERMES_HOME\plugins\hermuse equals the plugin assets of the installed app" @((Join-Path $Logs 'plugin-diff.txt'))
  Add-Verdict $id 'feed-endpoint' $true 'GET /api/plugins/hermuse/feed on the supervised backend' @($feedJson)
  Add-Verdict $id 'goals-endpoint' (Invoke-Rest GET /api/plugins/hermuse/goals (Join-Path $Probe 'goals.json')) `
    'GET /api/plugins/hermuse/goals' @((Join-Path $Probe 'goals.json'))
  $cron1 = Join-Path $Probe 'cron-1.json'
  Wait-Until (T 120) 5 {
    (Invoke-Rest GET /api/plugins/hermuse/cron $cron1) -and
    @((Read-Json $cron1).body.jobs | Where-Object { $_.registered -and $_.enabled }).Count -eq 4
  } | Out-Null
  $count = @((Read-Json $cron1).body.jobs | Where-Object { $_.registered -and $_.enabled }).Count
  Add-Verdict $id 'jobs-registered' ($count -eq 4) "$count/4 Hermuse jobs registered and enabled" @($cron1)
  $jobsFile = Join-Path $HermesHome 'cron\jobs.json'
  Copy-Item $jobsFile (Join-Path $Logs 'cron-jobs.json') -ErrorAction SilentlyContinue
  $jobs = Read-Json $jobsFile
  $ids = Get-CronIds $cron1
  $ran = @(if ($jobs) { $jobs.jobs | Where-Object { $ids -contains $_.id -and $null -ne $_.last_run_at } })
  Add-Verdict $id 'jobs-not-run' ($ran.Count -eq 0) 'registered jobs have no run recorded (registration is not execution)' `
    @((Join-Path $Logs 'cron-jobs.json'))
  # Idempotent enablement: a restart runs the setup again, never duplicates.
  $totalBefore = if ($jobs) { @($jobs.jobs).Count } else { 0 }
  Stop-App | Out-Null
  if ((Start-App 'plugin-restart') -and (Wait-Until (T 600) 5 { Test-BackendUp })) {
    $cron2 = Join-Path $Probe 'cron-2.json'
    Invoke-Rest GET /api/plugins/hermuse/cron $cron2 | Out-Null
    $after = Read-Json $jobsFile
    $same = ((Get-CronIds $cron1) -join ',') -eq ((Get-CronIds $cron2) -join ',') -and (@($after.jobs).Count -eq $totalBefore)
    Add-Verdict $id 'enable-idempotent' $same 'same 4 job ids and no new job after a restart' @($cron2)
  } else {
    Add-Check $id 'enable-idempotent' 'fail' 'no backend after a restart' @((Save-Shot 'restart-no-backend'))
  }
  Invoke-UiClick $UiBackToChat 20 | Out-Null
  D rail 2 $WindowTitle *> $null
  $feed = Wait-UiText $UiFeed 30
  D rail 4 $WindowTitle *> $null
  $goals = Wait-UiText $UiGoals 30
  Add-Check $id 'feed-goals-ui' 'manual-gate' 'confirm Feed and Goals load, and the 4 registered jobs are not shown as executed' `
    @(($feed ?? (Save-Shot 'feed-missing')), ($goals ?? (Save-Shot 'goals-missing')))
  return $true
}

# Connections > the bridge card > its Connect button (see macos.sh).
function Invoke-BridgeConnect {
  Invoke-UiClick $UiBackToChat 10 | Out-Null
  if (-not (Invoke-UiClick $UiConnections 5)) {
    D rail last $WindowTitle *> $null
    if (-not (Invoke-UiClick $UiConnections 60)) { return $false }
  }
  D scroll up 60 $WindowTitle | Out-Null
  Start-Sleep -Seconds 1
  if (-not (Invoke-UiClick $UiSearchConnections 30 'any')) { return $false }
  D type $UiBridgeCard | Out-Null
  Start-Sleep -Seconds 2
  return (Invoke-UiClick $UiBridgeCard 30 'any') -and (Invoke-UiClick $UiConnect 30 'filled')
}

function Test-Bridge {
  $id = 'c6-bridge'
  $config = Join-Path $HermesHome 'cliproxy\config.yaml'
  if (-not (Invoke-BridgeConnect)) {
    Add-Check $id 'sidecar' 'manual-gate' "Connections > search '$UiBridgeCard' > '$UiConnect' not reachable by OCR: start a bridge by hand" `
      @((Save-Shot 'bridge-ui-missing'))
    return
  }
  $probe = Join-Path $Probe 'cliproxy.json'
  $expectExe = Join-Path $InstallDir 'cliproxy.exe'
  $up = (Wait-Until (T 120) 3 { (Test-Path $config) -and (Get-Item $config).Length -gt 0 }) -and
    (Wait-Until (T 120) 3 { D cliproxy --config $config --expect-exe $expectExe *> $probe; $LASTEXITCODE -eq 0 })
  if ($up) {
    Add-Check $id 'sidecar' 'pass' "CLIProxy started from $expectExe; management API: 401 without key, 200 with it" @($probe, (Save-Shot 'bridge-login'))
  } else {
    Add-Check $id 'sidecar' 'fail' 'the bridge did not start from the bundle slot' @($probe, (Save-Shot 'bridge'))
  }
  Invoke-UiClick $UiCancel 30 | Out-Null
  # The login is only started: no subscription credential may exist.
  $authDir = if (Test-Path $config) {
    (Select-String -Path $config -Pattern '^auth-dir: *"(.*)"$' | Select-Object -First 1).Matches.Groups[1].Value -replace '\\\\', '\'
  }
  $files = @(if ($authDir -and (Test-Path $authDir)) { Get-ChildItem -LiteralPath $authDir -Recurse -File | ForEach-Object FullName })
  $files | Out-File (Join-Path $Logs 'cliproxy-auth-files.txt')
  Add-Verdict $id 'no-subscription-credential' ($files.Count -eq 0) `
    "no subscription credential stored in $(if ($authDir) { $authDir } else { 'the bridge auth dir' }) (login started, never completed)" `
    @((Join-Path $Logs 'cliproxy-auth-files.txt'))
}

function Test-Computer {
  $id = 'c7-computer'
  $status = Join-Path $Probe 'computer-status.json'
  Invoke-Rest GET /api/plugins/hermuse/computer/status $status | Out-Null
  $state = (Read-Json $status).body.state
  Add-Verdict $id 'docker-missing-reported' ($state -eq 'docker_missing') "no Docker on the runner: the plugin reports '$state'" @($status)
  Invoke-UiClick $UiBackToChat 10 | Out-Null
  D rail 2 $WindowTitle *> $null
  $png = Wait-UiText $UiDockerNotice 30
  if (-not $png) { $png = Save-Shot 'docker-notice-missing' }
  Add-Check $id 'computer' 'manual-gate' `
    ("the hosted Windows runner has no nested virtualization for a Docker engine (phase 2: WSL2 + docker.io): confirm the Docker " +
    "notice here, then attest the agent's computer (image pull, doctor, frames, take control) on a real Windows 11 machine") @($png, $status)
}

function Test-Lifecycle {
  $id = 'c10-lifecycle'
  if (-not (Stop-App)) { Add-Check $id 'app-closed' 'fail' 'the app did not exit on WM_CLOSE'; return }
  $before = Join-Path $Logs 'data-before.txt'
  $after = Join-Path $Logs 'data-after-uninstall.txt'
  & { '## app data'; Get-TreeManifest $AppData; '## HERMES_HOME'; Get-TreeManifest $HermesHome } | Out-File $before
  D dpapi decrypt $SecretFile *> (Join-Path $Probe 'secret-store-before.json')
  $uninstaller = Join-Path $InstallDir 'unins000.exe'
  $log = Join-Path $Logs 'setup-uninstall.log'
  Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$log`"" -Wait
  # The uninstaller runs on from a temporary copy of itself: wait for its result.
  $gone = Wait-Until (T 180) 2 { -not (Test-Path $AppExe) -and -not (Test-Path $UninstallKey) }
  Add-Verdict $id 'uninstall' ($gone -and -not (Test-Path $StartMenuLink)) `
    'silent uninstall: app files, Start menu shortcut and HKCU uninstall entry removed' @($log)
  & { '## app data'; Get-TreeManifest $AppData; '## HERMES_HOME'; Get-TreeManifest $HermesHome } | Out-File $after
  $same = $null -eq (Compare-Object (Get-Content $before) (Get-Content $after))
  Add-Verdict $id 'data-kept' $same 'app data (database, journal, secret store) and HERMES_HOME identical after the uninstall' @($before, $after)
  D dpapi decrypt $SecretFile *> (Join-Path $Probe 'secret-store-after.json')
  $keysBefore = (Read-Json (Join-Path $Probe 'secret-store-before.json')).keys -join ','
  $keysAfter = (Read-Json (Join-Path $Probe 'secret-store-after.json')).keys -join ','
  Add-Verdict $id 'secrets-kept' ($LASTEXITCODE -eq 0 -and $keysAfter -and $keysAfter -eq $keysBefore) `
    'the secret store still opens with the same entries' @((Join-Path $Probe 'secret-store-after.json'))
  # Reinstall: the app finds its local instance again, no Welcome screen.
  $proc = Start-Process -FilePath $Setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
  if ($proc.ExitCode -eq 0 -and (Start-App 'reinstalled') -and (Wait-Until (T 600) 5 { Test-BackendUp })) {
    $png = Save-Shot 'reinstalled'
    D locate $png $UiLocalChoice | Out-Null
    Add-Verdict $id 'reinstall-reuses-data' ($LASTEXITCODE -ne 0) `
      'after a reinstall the app supervises the kept local instance again (no Welcome screen)' @($png, (Join-Path $Probe 'backend.json'))
  } else {
    Add-Check $id 'reinstall-reuses-data' 'fail' 'no backend after reinstalling' @((Save-Shot 'reinstall-no-backend'))
  }
}

function Start-Recorder {
  $frames = Join-Path $Evid 'frames'
  New-Item -ItemType Directory -Force $frames | Out-Null
  $script:Recorder = Start-Job -ScriptBlock {
    param($magick, $dir)
    while ($true) {
      & $magick 'screenshot:[0]' -resize 50% -quality 60 (Join-Path $dir ("{0}.jpg" -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())) 2>$null
      Start-Sleep -Seconds 5
    }
  } -ArgumentList (Get-Command magick).Source, $frames
}

function Invoke-Fresh {
  foreach ($id in 'c0-test-base', 'c1-launch', 'c3-keyring', 'c4-hermes', 'c5-plugin', 'c6-bridge', 'c7-computer', 'c10-lifecycle') {
    $Expected.Add($id)
  }
  Test-Base
  Start-Recorder
  if (-not (Test-Launch)) { return }
  if (-not (Test-Hermes)) { return }
  Test-Keyring
  if (-not (Test-Plugin)) { return }
  Test-Bridge
  Test-Computer
  Test-Lifecycle
}

$exitCode = 0
Log "scenario $Scenario (setup) on $Runner, run $RunId, $(Split-Path $Setup -Leaf)"
try {
  Invoke-Fresh
} catch {
  $exitCode = 1
  Log "scenario error: $_ $($_.ScriptStackTrace)"
} finally {
  if ($Recorder) { Stop-Job $Recorder -ErrorAction SilentlyContinue; Remove-Job $Recorder -Force -ErrorAction SilentlyContinue }
  Stop-App 120 | Out-Null
  Complete-Results $exitCode
  Log "results written to $Res"
}
exit 0
