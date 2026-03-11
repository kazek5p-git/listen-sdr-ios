param(
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRepoDir = "~/listen-sdr-ios",
  [string]$RepoUrl = "https://github.com/kazek5p-git/listen-sdr-ios.git",
  [int]$StatusPollIntervalSeconds = 30,
  [int]$StatusTimeoutMinutes = 20
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RemoteDistributionP12Password)) {
  throw "Remote distribution .p12 password is missing. Set LISTENSDR_REMOTE_P12_PASSWORD in user environment or pass -RemoteDistributionP12Password."
}

$remoteScriptPath = Join-Path $PSScriptRoot "Run-ListenSDR-RemoteTestFlight.ps1"
if (-not (Test-Path $remoteScriptPath)) {
  throw "Remote TestFlight script not found: $remoteScriptPath"
}

& powershell -ExecutionPolicy Bypass -File $remoteScriptPath `
  -RemoteDistributionP12Password $RemoteDistributionP12Password `
  -RemoteHost $RemoteHost `
  -RemoteRepoDir $RemoteRepoDir `
  -RepoUrl $RepoUrl `
  -UploadToTestFlight `
  -WaitForTestFlightProcessing `
  -StatusPollIntervalSeconds $StatusPollIntervalSeconds `
  -StatusTimeoutMinutes $StatusTimeoutMinutes

if ($LASTEXITCODE -ne 0) {
  throw "End-to-end TestFlight pipeline failed."
}
