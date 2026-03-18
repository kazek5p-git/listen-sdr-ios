param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRoot = "~/.listen-sdr-local",
  [string]$OutputIpaPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "Listen-SDR-unsigned-local-latest.ipa"),
  [string]$LocalBuildLogPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "native-ios-build-local-latest.log"),
  [switch]$SkipInstall,
  [int]$InstallMaxAttempts = 3,
  [int]$InstallTimeoutSec = 180
)

$ErrorActionPreference = "Stop"

$remoteUnsignedScriptPath = Join-Path $PSScriptRoot "Build-ListenSDR-RemoteUnsigned.ps1"
if (-not (Test-Path $remoteUnsignedScriptPath)) {
  throw "Remote unsigned build script not found: $remoteUnsignedScriptPath"
}

$arguments = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $remoteUnsignedScriptPath,
  "-RepoRoot", $RepoRoot,
  "-RemoteHost", $RemoteHost,
  "-RemoteRoot", $RemoteRoot,
  "-OutputIpaPath", $OutputIpaPath,
  "-DownloadBuildLog",
  "-LocalBuildLogPath", $LocalBuildLogPath
)

if (-not $SkipInstall) {
  $arguments += @(
    "-InstallOnIPhone",
    "-InstallMaxAttempts", $InstallMaxAttempts,
    "-InstallTimeoutSec", $InstallTimeoutSec
  )
}

& powershell @arguments
if ($LASTEXITCODE -ne 0) {
  throw "Local remote build wrapper failed."
}
