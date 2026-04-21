param(
  [ValidateSet("login", "temporary-p12")]
  [string]$SigningMode = "login",
  [string]$RemoteLoginKeychainPassword = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD", "User"),
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRepoDir = "~/listen-sdr-ios",
  [string]$RepoUrl = "https://github.com/kazek5p-git/listen-sdr-ios.git",
  [string]$ReleaseNotesRoot,
  [string]$BetaGroupName = "alfa",
  [string]$BetaGroupId = "a0c0017c-8e47-46e6-9185-6fdc948c91f8",
  [string]$PublicBetaGroupName = "publiczna",
  [string]$PublicBetaGroupId = "f4e0a82c-19ea-4aa2-aaef-fe0d930d4126",
  [switch]$DryRun,
  [switch]$SkipPreflight,
  [switch]$SkipMetadataPublish,
  [switch]$SkipPublicGroup,
  [switch]$SkipRemoteBuild,
  [switch]$SkipWaitForProcessing,
  [int]$StatusPollIntervalSeconds = 10,
  [int]$StatusTimeoutMinutes = 20
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ReleaseNotesRoot)) {
  $ReleaseNotesRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "release\testflight"
}

$resumeStatePath = Join-Path $ReleaseNotesRoot "last-publish-state.json"

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

$publicScriptPath = Join-Path $PSScriptRoot "Publish-ListenSDR-PublicTestFlight.ps1"
if (-not $SkipMetadataPublish -and -not $SkipPublicGroup -and -not (Test-Path $publicScriptPath)) {
  throw "Public TestFlight script not found: $publicScriptPath"
}

$preflightScriptPath = Join-Path $PSScriptRoot "Test-ListenSDR-TestFlightPreflight.ps1"
if (-not $SkipPreflight -and -not (Test-Path $preflightScriptPath)) {
  throw "TestFlight preflight script not found: $preflightScriptPath"
}

if (-not $SkipPreflight -and -not $SkipRemoteBuild) {
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

if (-not $SkipRemoteBuild) {
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
    if (-not $SkipWaitForProcessing) {
      $arguments.WaitForTestFlightProcessing = $true
    }
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
  if ($SkipWaitForProcessing -and -not $DryRun) {
    Write-Host "Skipping ASC processing wait after upload. Use -SkipRemoteBuild later to resume metadata and group publish."
  }
  & $remoteScriptPath @arguments

  if ($LASTEXITCODE -ne 0) {
    throw "End-to-end TestFlight pipeline failed."
  }

  if ($SkipWaitForProcessing -and -not $DryRun) {
    $resumeState = [ordered]@{
      releaseNotesRoot = $ReleaseNotesRoot
      betaGroupName = $BetaGroupName
      betaGroupId = $BetaGroupId
      publicBetaGroupName = $PublicBetaGroupName
      publicBetaGroupId = $PublicBetaGroupId
      createdAt = (Get-Date).ToString("o")
      resumeCommand = "powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\Run-ListenSDR-TestFlightEndToEnd.ps1`" -SkipRemoteBuild"
    }

    $resumeState | ConvertTo-Json -Depth 6 | Set-Content -Path $resumeStatePath -Encoding utf8

    if (-not $SkipMetadataPublish) {
      Write-Host ""
      Write-Host "Skipping metadata publish because ASC processing wait was skipped."
      Write-Host ("Resume later with: " + $resumeState.resumeCommand)
      Write-Host ("State file: " + $resumeStatePath)
      return
    }
  }
} else {
  Write-Host ""
  Write-Host "==> Resume mode"
  Write-Host "Skipping remote build/upload and continuing from existing App Store Connect build."
}

if (-not $SkipMetadataPublish) {
  Write-Host ""
  Write-Host ("==> Internal metadata " + ($(if ($DryRun) { "validation" } else { "publish" })))

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

  if (-not $SkipPublicGroup) {
    Write-Host ""
    Write-Host ("==> Public metadata " + ($(if ($DryRun) { "validation" } else { "publish" })))

    $publicMetadataArguments = @{
      ReleaseNotesRoot = $ReleaseNotesRoot
      BetaGroupName = $PublicBetaGroupName
      BetaGroupId = $PublicBetaGroupId
    }
    if ($DryRun) {
      $publicMetadataArguments.ValidateOnly = $true
    }

    & $metadataScriptPath @publicMetadataArguments

    if ($LASTEXITCODE -ne 0) {
      throw "Public TestFlight metadata step failed."
    }

    if (-not $DryRun) {
      Write-Host ""
      Write-Host "==> Public TestFlight review"
      & $publicScriptPath -PublicBetaGroupName $PublicBetaGroupName -PublicBetaGroupId $PublicBetaGroupId

      if ($LASTEXITCODE -ne 0) {
        throw "Public TestFlight submission step failed."
      }
    }
  }
}
