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
  [switch]$DryRun,
  [switch]$SkipPreflight,
  [switch]$SkipMetadataPublish,
  [int]$StatusPollIntervalSeconds = 10,
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

$preflightScriptPath = Join-Path $PSScriptRoot "Test-ListenSDR-TestFlightPreflight.ps1"
if (-not $SkipPreflight -and -not (Test-Path $preflightScriptPath)) {
  throw "TestFlight preflight script not found: $preflightScriptPath"
}

if (-not $SkipPreflight) {
  Write-Host ""
  Write-Host ("==> TestFlight preflight (" + ($(if ($DryRun) { "DryRun" } else { "Publish" })) + ")")

  $preflightArguments = @{
    RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    RemoteHost = $RemoteHost
    ReleaseNotesRoot = $ReleaseNotesRoot
    SigningMode = $SigningMode
    Mode = $(if ($DryRun) { "DryRun" } else { "Publish" })
  }

  if ($SigningMode -eq "login") {
    if (-not [string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
      $preflightArguments.RemoteLoginKeychainPassword = $RemoteLoginKeychainPassword
    }
  } else {
    $preflightArguments.RemoteDistributionP12Password = $RemoteDistributionP12Password
  }

  & $preflightScriptPath @preflightArguments
  if ($LASTEXITCODE -ne 0) {
    throw "TestFlight preflight failed."
  }
}

$arguments = @{
  SigningMode = $SigningMode
  RemoteHost = $RemoteHost
  RemoteRepoDir = $RemoteRepoDir
  RepoUrl = $RepoUrl
  StatusPollIntervalSeconds = $StatusPollIntervalSeconds
  StatusTimeoutMinutes = $StatusTimeoutMinutes
}

if (-not $DryRun) {
  $arguments.UploadToTestFlight = $true
  $arguments.WaitForTestFlightProcessing = $true
}

if ($SigningMode -eq "login") {
  if (-not [string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
    $arguments.RemoteLoginKeychainPassword = $RemoteLoginKeychainPassword
  }
} else {
  $arguments.RemoteDistributionP12Password = $RemoteDistributionP12Password
}

Write-Host ""
Write-Host ("==> Remote build (" + ($(if ($DryRun) { "DryRun" } else { "Publish" })) + ")")
& $remoteScriptPath @arguments

if ($LASTEXITCODE -ne 0) {
  throw "End-to-end TestFlight pipeline failed."
}

if (-not $SkipMetadataPublish) {
  Write-Host ""
  Write-Host ("==> Metadata " + ($(if ($DryRun) { "validation" } else { "publish" })))

  $metadataArguments = @{
    ReleaseNotesRoot = $ReleaseNotesRoot
    BetaGroupName = $BetaGroupName
    BetaGroupId = $BetaGroupId
  }
  if ($DryRun) {
    $metadataArguments.ValidateOnly = $true
  }

  & $metadataScriptPath @metadataArguments

  if ($LASTEXITCODE -ne 0) {
    throw "TestFlight metadata step failed."
  }
}
