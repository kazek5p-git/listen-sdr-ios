param(
  [ValidateSet("login", "temporary-p12")]
  [string]$SigningMode = "login",
  [string]$RemoteLoginKeychainPassword = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD", "User"),
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRepoDir = "~/listen-sdr-ios",
  [string]$RepoUrl = "https://github.com/kazek5p-git/listen-sdr-ios.git",
  [string]$ReleaseNotesRoot,
  [string]$BetaGroupName = "wewnetrzna",
  [string]$BetaGroupId = "89359342-cf9d-480b-9c75-8e34a7fef728",
  [switch]$SkipMetadataPublish,
  [int]$StatusPollIntervalSeconds = 30,
  [int]$StatusTimeoutMinutes = 20
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ReleaseNotesRoot)) {
  $ReleaseNotesRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "release\testflight"
}

if ($SigningMode -eq "temporary-p12" -and [string]::IsNullOrWhiteSpace($RemoteDistributionP12Password)) {
  throw "Remote distribution .p12 password is missing. Set LISTENSDR_REMOTE_P12_PASSWORD in user environment or pass -RemoteDistributionP12Password."
}

$remoteScriptPath = Join-Path $PSScriptRoot "Run-ListenSDR-RemoteTestFlight.ps1"
if (-not (Test-Path $remoteScriptPath)) {
  throw "Remote TestFlight script not found: $remoteScriptPath"
}

$metadataScriptPath = Join-Path $PSScriptRoot "Publish-ListenSDR-TestFlightMetadata.ps1"
if (-not $SkipMetadataPublish -and -not (Test-Path $metadataScriptPath)) {
  throw "TestFlight metadata script not found: $metadataScriptPath"
}

$arguments = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $remoteScriptPath,
  "-SigningMode", $SigningMode,
  "-RemoteHost", $RemoteHost,
  "-RemoteRepoDir", $RemoteRepoDir,
  "-RepoUrl", $RepoUrl,
  "-UploadToTestFlight",
  "-WaitForTestFlightProcessing",
  "-StatusPollIntervalSeconds", $StatusPollIntervalSeconds,
  "-StatusTimeoutMinutes", $StatusTimeoutMinutes
)

if ($SigningMode -eq "login") {
  if (-not [string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
    $arguments += @("-RemoteLoginKeychainPassword", $RemoteLoginKeychainPassword)
  }
} else {
  $arguments += @("-RemoteDistributionP12Password", $RemoteDistributionP12Password)
}

& powershell @arguments

if ($LASTEXITCODE -ne 0) {
  throw "End-to-end TestFlight pipeline failed."
}

if (-not $SkipMetadataPublish) {
  & powershell -ExecutionPolicy Bypass -File $metadataScriptPath `
    -ReleaseNotesRoot $ReleaseNotesRoot `
    -BetaGroupName $BetaGroupName `
    -BetaGroupId $BetaGroupId

  if ($LASTEXITCODE -ne 0) {
    throw "TestFlight metadata publish failed."
  }
}
