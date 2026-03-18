param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$AppleTeamId = [Environment]::GetEnvironmentVariable("EXPO_APPLE_TEAM_ID", "User"),
  [string]$InfoPlistPath,
  [string]$ReleaseNotesRoot,
  [string]$RemoteHost = "mac_axela",
  [ValidateSet("login", "temporary-p12")]
  [string]$SigningMode = "login",
  [string]$RemoteLoginKeychainPassword = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD", "User"),
  [string]$RemoteDistributionP12Path = "~/EXPORT_FOR_KAZEK/Apple_Distribution_Mieczysaw_Bk_9N975WV782_AxelPong.p12",
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [ValidateSet("Publish", "DryRun")]
  [string]$Mode = "Publish",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-DefaultAscApiKeyPath {
  param([string]$CurrentValue)

  $candidates = @(
    $CurrentValue,
    "C:\Users\Kazek\Desktop\Mac i logowanie\AuthKey_RDRPTFY7U4.p8",
    "C:\Users\Kazek\Desktop\iOS\AuthKey_RDRPTFY7U4.p8"
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $CurrentValue
}

function Get-ReleaseInfoFromInfoPlist {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Info.plist not found: $Path"
  }

  $content = Get-Content $Path -Raw
  $shortVersionMatch = [regex]::Match($content, '<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>')
  $buildVersionMatch = [regex]::Match($content, '<key>CFBundleVersion</key>\s*<string>([^<]+)</string>')

  if (-not $shortVersionMatch.Success -or -not $buildVersionMatch.Success) {
    throw "Unable to read CFBundleShortVersionString or CFBundleVersion from Info.plist."
  }

  return [pscustomobject]@{
    marketingVersion = $shortVersionMatch.Groups[1].Value.Trim()
    buildVersion = $buildVersionMatch.Groups[1].Value.Trim()
  }
}

function Get-ListenSDRSecretFilePath {
  param([Parameter(Mandatory = $true)][string]$SecretName)

  $baseDir = Join-Path $env:APPDATA "ListenSDR\secrets"
  return Join-Path $baseDir ($SecretName + ".txt")
}

function Read-ListenSDRSecret {
  param([Parameter(Mandatory = $true)][string]$SecretName)

  $secretPath = Get-ListenSDRSecretFilePath -SecretName $SecretName
  if (-not (Test-Path $secretPath)) {
    return $null
  }

  $encrypted = Get-Content -Path $secretPath -Raw
  if ([string]::IsNullOrWhiteSpace($encrypted)) {
    return $null
  }

  try {
    $secureValue = ConvertTo-SecureString -String $encrypted
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
      return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
      if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
      }
    }
  } catch {
    throw "Unable to read stored secret '$SecretName' from $secretPath. Delete the file and store the secret again."
  }
}

function Add-Check {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][ValidateSet("pass", "warning", "fail")][string]$Status,
    [Parameter(Mandatory = $true)][string]$Detail
  )

  $script:checks.Add([pscustomobject]@{
      name = $Name
      status = $Status
      detail = $Detail
    }) | Out-Null
}

function Try-ParseInt {
  param([string]$Value)

  $parsed = 0
  if ([int]::TryParse($Value, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Invoke-CommandCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Detail,
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
  )

  try {
    & $ScriptBlock | Out-Null
    Add-Check -Name $Name -Status "pass" -Detail $Detail
    return $true
  } catch {
    Add-Check -Name $Name -Status "fail" -Detail $_.Exception.Message
    return $false
  }
}

if ([string]::IsNullOrWhiteSpace($InfoPlistPath)) {
  $InfoPlistPath = Join-Path $RepoRoot "native-ios\ListenSDR\Info.plist"
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotesRoot)) {
  $ReleaseNotesRoot = Join-Path $RepoRoot "release\testflight"
}
if ([string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
  $RemoteLoginKeychainPassword = Read-ListenSDRSecret -SecretName "remote-login-keychain-password"
}

$AscApiKeyPath = Resolve-DefaultAscApiKeyPath -CurrentValue $AscApiKeyPath
$checks = [System.Collections.Generic.List[object]]::new()
$releaseInfo = $null
$metadataValidation = $null
$statusPayload = $null
$latestAscBuildVersion = $null
$expectedNextBuildVersion = $null
$buildNumberStatus = "unknown"
$uploadReady = $false

Invoke-CommandCheck -Name "repo" -Detail "Repository root exists." -ScriptBlock {
  if (-not (Test-Path $RepoRoot)) {
    throw "Repository root not found: $RepoRoot"
  }
} | Out-Null

Invoke-CommandCheck -Name "tools" -Detail "Local tools git/ssh/scp/python are available." -ScriptBlock {
  $requiredCommands = @("git", "ssh", "scp", "python")
  $missingCommands = @()
  foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
      $missingCommands += $commandName
    }
  }
  if ($missingCommands.Count -gt 0) {
    throw ("Missing commands: " + ($missingCommands -join ", "))
  }
} | Out-Null

Invoke-CommandCheck -Name "asc-auth" -Detail "App Store Connect credentials are present." -ScriptBlock {
  if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) {
    throw "ASC API key file not found."
  }
  if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
    throw "ASC key ID or issuer ID is missing."
  }
  if ([string]::IsNullOrWhiteSpace($AppleTeamId)) {
    throw "Apple team ID is missing."
  }
} | Out-Null

Invoke-CommandCheck -Name "git-status" -Detail "Repository worktree is clean for remote TestFlight build." -ScriptBlock {
  $status = @(& git -C $RepoRoot status --short | Where-Object {
      $_ -notmatch 'sideloadlydaemon\.log$' -and
      $_ -notmatch '^\s*[MADRCU?]{1,2}\s+scripts/Run-ListenSDR-RemoteTestFlight\.ps1$'
    })
  if ($status.Count -gt 0) {
    throw "Repository has uncommitted changes."
  }
} | Out-Null

Invoke-CommandCheck -Name "info-plist" -Detail "Info.plist contains marketing version and build version." -ScriptBlock {
  $script:releaseInfo = Get-ReleaseInfoFromInfoPlist -Path $InfoPlistPath
} | Out-Null

$metadataScriptPath = Join-Path $PSScriptRoot "Publish-ListenSDR-TestFlightMetadata.ps1"
Invoke-CommandCheck -Name "release-notes" -Detail "Release notes exist for the current marketing version and build." -ScriptBlock {
  if (-not (Test-Path $metadataScriptPath)) {
    throw "Metadata script not found: $metadataScriptPath"
  }

  $rawMetadata = & $metadataScriptPath `
    -RepoRoot $RepoRoot `
    -BundleId $BundleId `
    -InfoPlistPath $InfoPlistPath `
    -ReleaseNotesRoot $ReleaseNotesRoot `
    -ValidateOnly `
    -Json
  if ($LASTEXITCODE -ne 0) {
    throw "Metadata validation failed."
  }

  $script:metadataValidation = $rawMetadata | ConvertFrom-Json
  if (-not $script:metadataValidation.ok) {
    throw "Metadata validation returned failure."
  }
} | Out-Null

$statusScriptPath = Join-Path $PSScriptRoot "Check-ListenSDR-TestFlightStatus.ps1"
Invoke-CommandCheck -Name "asc-status" -Detail "Latest TestFlight builds are readable from App Store Connect." -ScriptBlock {
  if (-not (Test-Path $statusScriptPath)) {
    throw "Status script not found: $statusScriptPath"
  }

  $rawStatus = & $statusScriptPath `
    -BundleId $BundleId `
    -AscApiKeyPath $AscApiKeyPath `
    -AscKeyId $AscKeyId `
    -AscIssuerId $AscIssuerId `
    -MaxResults 20 `
    -Json
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read TestFlight status."
  }

  $script:statusPayload = $rawStatus | ConvertFrom-Json
  if (-not $script:statusPayload.ok) {
    throw "App Store Connect status payload is not OK."
  }
} | Out-Null

if ($null -ne $statusPayload -and $statusPayload.builds -and $statusPayload.builds.Count -gt 0 -and $null -ne $releaseInfo) {
  $latestAscBuildVersion = $statusPayload.builds[0].version
  $latestAscBuildInt = Try-ParseInt -Value $latestAscBuildVersion
  $localBuildInt = Try-ParseInt -Value $releaseInfo.buildVersion

  if ($null -eq $latestAscBuildInt -or $null -eq $localBuildInt) {
    $buildNumberStatus = "non_numeric"
    Add-Check -Name "build-number" -Status "fail" -Detail "Build number is not numeric. Local=$($releaseInfo.buildVersion), ASC=$latestAscBuildVersion."
  } else {
    $expectedNextBuildVersion = [string]($latestAscBuildInt + 1)
    switch ($localBuildInt) {
      { $_ -eq ($latestAscBuildInt + 1) } {
        $buildNumberStatus = "ready_to_publish"
        $uploadReady = $true
        Add-Check -Name "build-number" -Status "pass" -Detail ("Local build {0} is ready. Latest ASC build is {1}, expected next is {2}." -f $releaseInfo.buildVersion, $latestAscBuildVersion, $expectedNextBuildVersion)
        break
      }
      { $_ -eq $latestAscBuildInt } {
        $buildNumberStatus = "already_published"
        $status = if ($Mode -eq "DryRun") { "warning" } else { "fail" }
        Add-Check -Name "build-number" -Status $status -Detail ("Local build {0} matches the latest ASC build. Increment to {1} before the next TestFlight upload." -f $releaseInfo.buildVersion, $expectedNextBuildVersion)
        break
      }
      { $_ -lt ($latestAscBuildInt + 1) } {
        $buildNumberStatus = "behind"
        $status = if ($Mode -eq "DryRun") { "warning" } else { "fail" }
        Add-Check -Name "build-number" -Status $status -Detail ("Local build {0} is behind. Latest ASC build is {1}; next allowed build is {2}." -f $releaseInfo.buildVersion, $latestAscBuildVersion, $expectedNextBuildVersion)
        break
      }
      default {
        $buildNumberStatus = "ahead"
        $status = if ($Mode -eq "DryRun") { "warning" } else { "fail" }
        Add-Check -Name "build-number" -Status $status -Detail ("Local build {0} skips the expected next ASC build {1}." -f $releaseInfo.buildVersion, $expectedNextBuildVersion)
        break
      }
    }
  }
} elseif ($null -ne $releaseInfo) {
  $buildNumberStatus = "no_asc_builds"
  $uploadReady = $true
  Add-Check -Name "build-number" -Status "pass" -Detail ("No existing ASC builds found. Local build {0} can be treated as the first uploaded build." -f $releaseInfo.buildVersion)
}

Invoke-CommandCheck -Name "remote-host" -Detail ("Remote host {0} is reachable and has xcodebuild." -f $RemoteHost) -ScriptBlock {
  $command = "command -v xcodebuild >/dev/null 2>&1 && xcrun --find altool >/dev/null 2>&1 && printf READY"
  $output = ssh $RemoteHost $command
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to connect to remote host or required Xcode tools are missing."
  }
  if (($output | Out-String).Trim() -ne "READY") {
    throw "Unexpected remote host response."
  }
} | Out-Null

if ($SigningMode -eq "login") {
  Invoke-CommandCheck -Name "signing" -Detail "Login keychain signing prerequisites are present." -ScriptBlock {
    if ([string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
      throw "Remote login keychain password is missing."
    }

    $command = 'test -f "$HOME/Library/Keychains/login.keychain-db" && security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db" | grep -q ''Apple Distribution:'' && printf READY'
    $output = ssh $RemoteHost $command
    if ($LASTEXITCODE -ne 0) {
      throw "Apple Distribution identity not found in remote login keychain."
    }
    if (($output | Out-String).Trim() -ne "READY") {
      throw "Unexpected signing check response."
    }
  } | Out-Null
} else {
  Invoke-CommandCheck -Name "signing" -Detail "Temporary .p12 signing prerequisites are present." -ScriptBlock {
    if ([string]::IsNullOrWhiteSpace($RemoteDistributionP12Password)) {
      throw "Remote distribution .p12 password is missing."
    }

    $command = "test -f $RemoteDistributionP12Path && printf READY"
    $output = ssh $RemoteHost $command
    if ($LASTEXITCODE -ne 0) {
      throw "Remote distribution .p12 file not found."
    }
    if (($output | Out-String).Trim() -ne "READY") {
      throw "Unexpected signing check response."
    }
  } | Out-Null
}

$failedChecks = @($checks | Where-Object { $_.status -eq "fail" })
$warningChecks = @($checks | Where-Object { $_.status -eq "warning" })
$ok = $failedChecks.Count -eq 0

$result = [pscustomobject]@{
  ok = $ok
  mode = $Mode
  bundleId = $BundleId
  marketingVersion = if ($null -ne $releaseInfo) { $releaseInfo.marketingVersion } else { $null }
  buildVersion = if ($null -ne $releaseInfo) { $releaseInfo.buildVersion } else { $null }
  latestAscBuildVersion = $latestAscBuildVersion
  expectedNextBuildVersion = $expectedNextBuildVersion
  buildNumberStatus = $buildNumberStatus
  uploadReady = $uploadReady
  checks = @($checks)
  warningCount = $warningChecks.Count
  failureCount = $failedChecks.Count
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8
} else {
  Write-Host ("Mode: " + $result.mode)
  Write-Host ("Bundle ID: " + $result.bundleId)
  if ($result.marketingVersion -and $result.buildVersion) {
    Write-Host ("Local version: " + $result.marketingVersion + " (" + $result.buildVersion + ")")
  }
  if ($result.latestAscBuildVersion) {
    $nextInfo = if ($result.expectedNextBuildVersion) { " | expected next: " + $result.expectedNextBuildVersion } else { "" }
    Write-Host ("Latest ASC build: " + $result.latestAscBuildVersion + $nextInfo)
  }
  foreach ($check in $result.checks) {
    Write-Host ("[{0}] {1}: {2}" -f $check.status.ToUpperInvariant(), $check.name, $check.detail)
  }
  if ($result.ok) {
    Write-Host "Preflight result: PASS"
  } else {
    Write-Host "Preflight result: FAIL"
  }
}

if (-not $ok) {
  exit 1
}
