#Requires -Version 7.2
<#
.SYNOPSIS
Signs PE files of the Hermuse Agent Windows release (Authenticode SHA-256
with an RFC 3161 timestamp) and checks every signature it made.

.DESCRIPTION
  pwsh -NoProfile -File packaging/windows/sign.ps1 <file> [<file>...]

build-release.ps1 calls it for cliproxy.exe and the bundle; Inno Setup calls
it for the uninstaller and Setup.exe (ISCC /Shermuse=...). The signer comes
from the environment, which both pass on:

- WINDOWS_SIGNING_ENDPOINT, WINDOWS_SIGNING_ACCOUNT, WINDOWS_SIGNING_PROFILE:
  Azure Artifact Signing (formerly Trusted Signing). The Windows SDK signtool
  loads the dlib of the pinned Microsoft.ArtifactSigning.Client package,
  which signs with DefaultAzureCredential (in CI the Azure CLI session of
  azure/login with OIDC); managed identity, Visual Studio and interactive
  credentials are excluded. Every signature must verify as Valid.
- HERMUSE_TEST_SIGNING_PFX, HERMUSE_TEST_SIGNING_PASSWORD: the throwaway,
  untrusted certificate of build-release.ps1 -TestSigning. Only the signer
  and the timestamp are checked; such files do not count as signed.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory, ValueFromRemainingArguments)]
  [string[]]$Path
)

. (Join-Path $PSScriptRoot 'lib/common.ps1')

$artifactSigning = @(@($env:WINDOWS_SIGNING_ENDPOINT, $env:WINDOWS_SIGNING_ACCOUNT, $env:WINDOWS_SIGNING_PROFILE) |
    Where-Object { $_ })
$testPfx = $env:HERMUSE_TEST_SIGNING_PFX
if ($artifactSigning.Count -notin 0, 3) {
  Stop-Hermuse 'WINDOWS_SIGNING_ENDPOINT, WINDOWS_SIGNING_ACCOUNT and WINDOWS_SIGNING_PROFILE are set together or not at all'
}
if ($artifactSigning.Count -eq 3 -and $testPfx) {
  Stop-Hermuse 'Artifact Signing and HERMUSE_TEST_SIGNING_PFX are exclusive'
}
if ($artifactSigning.Count -eq 0 -and -not $testPfx) {
  Stop-Hermuse 'no signer: set the WINDOWS_SIGNING_* variables (or HERMUSE_TEST_SIGNING_PFX)'
}

$files = @(foreach ($file in $Path) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-Hermuse "nothing to sign at $file" }
    (Resolve-Path -LiteralPath $file).ProviderPath
  })
$signtool = Find-SignTool
$timestamp = Get-LockValue 'windows.timestamp_url'
$work = Join-Path ([IO.Path]::GetTempPath()) "hermuse-sign-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $work | Out-Null
try {
  if ($testPfx) {
    $password = $env:HERMUSE_TEST_SIGNING_PASSWORD
    $expected = [Security.Cryptography.X509Certificates.X509Certificate2]::new($testPfx, $password).Thumbprint
    $arguments = @('sign', '/fd', 'SHA256', '/f', $testPfx, '/p', $password, '/tr', $timestamp, '/td', 'SHA256')
  } else {
    $client = Get-LockValue 'windows.artifact_signing_client'
    $cache = Join-Path (Get-HermuseToolsCache) 'artifact-signing'
    $package = Get-PinnedFile $client.url $client.sha256 (Join-Path $cache "$($client.package).$($client.version).nupkg") `
      "$($client.package) $($client.version)"
    $clientDir = Join-Path $cache $client.version
    if (-not (Test-Path -LiteralPath $clientDir)) {
      $partial = "$clientDir.partial"
      Remove-Item -Recurse -Force -LiteralPath $partial -ErrorAction SilentlyContinue
      [IO.Compression.ZipFile]::ExtractToDirectory($package, $partial)
      Move-Item -LiteralPath $partial -Destination $clientDir
    }
    $dlib = Join-Path $clientDir 'bin/x64/Azure.CodeSigning.Dlib.dll'
    if (-not (Test-Path -LiteralPath $dlib)) { Stop-Hermuse "no x64 dlib in $($client.package) $($client.version)" }
    $metadata = [ordered]@{
      Endpoint = $env:WINDOWS_SIGNING_ENDPOINT
      CodeSigningAccountName = $env:WINDOWS_SIGNING_ACCOUNT
      CertificateProfileName = $env:WINDOWS_SIGNING_PROFILE
      ExcludeCredentials = @(
        'ManagedIdentityCredential', 'WorkloadIdentityCredential', 'SharedTokenCacheCredential',
        'VisualStudioCredential', 'VisualStudioCodeCredential', 'AzurePowerShellCredential',
        'AzureDeveloperCliCredential', 'InteractiveBrowserCredential')
    }
    if ($env:GITHUB_RUN_ID) {
      $metadata.CorrelationId = "hermuse-agent-$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
    }
    $metadataFile = Join-Path $work 'metadata.json'
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metadataFile -Encoding utf8NoBOM
    $arguments = @('sign', '/v', '/debug', '/fd', 'SHA256', '/tr', $timestamp, '/td', 'SHA256',
      '/dlib', $dlib, '/dmdf', $metadataFile)
  }

  Write-HermuseLog "signing $($files.Count) file(s) with $(if ($testPfx) { 'the test certificate' } else { 'Artifact Signing' })"
  # Not Invoke-Native: the test password must not end up in an error message.
  & $signtool @arguments @files
  if ($LASTEXITCODE -ne 0) { Stop-Hermuse "signtool sign failed (exit $LASTEXITCODE)" }

  foreach ($file in $files) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($testPfx) {
      if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $expected) {
        Stop-Hermuse "$file is not signed by the test certificate ($($signature.Status))"
      }
    } elseif ($signature.Status -ne 'Valid') {
      Stop-Hermuse "$file signature is $($signature.Status): $($signature.StatusMessage)"
    }
    if ($null -eq $signature.TimeStamperCertificate) { Stop-Hermuse "$file has no timestamp" }
  }
} finally {
  Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}
