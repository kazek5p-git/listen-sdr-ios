param(
  [string]$RepoSlug = "kazek5p-git/listen-sdr-ios",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$AppleTeamId = [Environment]::GetEnvironmentVariable("EXPO_APPLE_TEAM_ID", "User"),
  [string]$DistCertP12Path,
  [string]$DistCertPassword,
  [string]$ProvisionProfilePath,
  [string]$KeychainPassword,
  [switch]$AllowPartial
)

$ErrorActionPreference = "Stop"

function Assert-Tooling {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "gh is not available in PATH."
  }
}

function Set-SecretValue {
  param(
    [string]$Name,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "Secret value for $Name is empty."
  }

  & gh secret set $Name --repo $RepoSlug --body $Value
  if ($LASTEXITCODE -ne 0) {
    throw "gh secret set failed for $Name"
  }
}

function Set-SecretFileBase64 {
  param(
    [string]$Name,
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "Path for $Name is empty."
  }
  if (-not (Test-Path $Path)) {
    throw "File for $Name not found: $Path"
  }

  $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path))
  $base64 = [Convert]::ToBase64String($bytes)
  Set-SecretValue -Name $Name -Value $base64
}

function New-StrongPassword {
  $bytes = New-Object byte[] 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', 'A').Replace('/', 'B')
}

Assert-Tooling

$missing = New-Object System.Collections.Generic.List[string]

if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) { $missing.Add("ASC_API_KEY_BASE64 source file (.p8)") }
if ([string]::IsNullOrWhiteSpace($AscKeyId)) { $missing.Add("ASC_KEY_ID") }
if ([string]::IsNullOrWhiteSpace($AscIssuerId)) { $missing.Add("ASC_ISSUER_ID") }
if ([string]::IsNullOrWhiteSpace($AppleTeamId)) { $missing.Add("APPLE_TEAM_ID") }
if ([string]::IsNullOrWhiteSpace($DistCertP12Path) -or -not (Test-Path $DistCertP12Path)) { $missing.Add("IOS_DIST_CERT_P12_BASE64 source file (.p12)") }
if ([string]::IsNullOrWhiteSpace($DistCertPassword)) { $missing.Add("IOS_DIST_CERT_PASSWORD") }
if ([string]::IsNullOrWhiteSpace($ProvisionProfilePath) -or -not (Test-Path $ProvisionProfilePath)) { $missing.Add("IOS_PROVISION_PROFILE_BASE64 source file (.mobileprovision)") }

if ([string]::IsNullOrWhiteSpace($KeychainPassword)) {
  $KeychainPassword = New-StrongPassword
}

Write-Host ""
Write-Host "==> Setting GitHub secrets for TestFlight"
Write-Host ("Repo: " + $RepoSlug)

Set-SecretValue -Name "ASC_KEY_ID" -Value $AscKeyId
Set-SecretValue -Name "ASC_ISSUER_ID" -Value $AscIssuerId
Set-SecretValue -Name "APPLE_TEAM_ID" -Value $AppleTeamId
Set-SecretFileBase64 -Name "ASC_API_KEY_BASE64" -Path $AscApiKeyPath
Set-SecretValue -Name "KEYCHAIN_PASSWORD" -Value $KeychainPassword

$haveDistributionInputs = (-not [string]::IsNullOrWhiteSpace($DistCertP12Path)) -and
  (-not [string]::IsNullOrWhiteSpace($DistCertPassword)) -and
  (-not [string]::IsNullOrWhiteSpace($ProvisionProfilePath)) -and
  (Test-Path $DistCertP12Path) -and
  (Test-Path $ProvisionProfilePath)

if ($haveDistributionInputs) {
  Set-SecretFileBase64 -Name "IOS_DIST_CERT_P12_BASE64" -Path $DistCertP12Path
  Set-SecretValue -Name "IOS_DIST_CERT_PASSWORD" -Value $DistCertPassword
  Set-SecretFileBase64 -Name "IOS_PROVISION_PROFILE_BASE64" -Path $ProvisionProfilePath
} elseif (-not $AllowPartial) {
  throw ("Missing distribution inputs: " + (($missing | Select-Object -Unique) -join ", "))
}

Write-Host ""
Write-Host "Configured secrets:"
Write-Host "- ASC_KEY_ID"
Write-Host "- ASC_ISSUER_ID"
Write-Host "- APPLE_TEAM_ID"
Write-Host "- ASC_API_KEY_BASE64"
Write-Host "- KEYCHAIN_PASSWORD"
if ($haveDistributionInputs) {
  Write-Host "- IOS_DIST_CERT_P12_BASE64"
  Write-Host "- IOS_DIST_CERT_PASSWORD"
  Write-Host "- IOS_PROVISION_PROFILE_BASE64"
}

if (-not $haveDistributionInputs) {
  Write-Host ""
  Write-Host "Still missing before signed TestFlight upload can work:"
  ($missing | Select-Object -Unique) | ForEach-Object { Write-Host ("- " + $_) }
}
