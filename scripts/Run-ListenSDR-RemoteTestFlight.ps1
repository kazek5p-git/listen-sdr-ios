param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRepoDir = "~/listen-sdr-ios",
  [string]$RepoUrl = "https://github.com/kazek5p-git/listen-sdr-ios.git",
  [string]$AscApiKeyPath = "C:\Users\Kazek\Desktop\Mac i logowanie\AuthKey_RDRPTFY7U4.p8",
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$AppleTeamId = [Environment]::GetEnvironmentVariable("EXPO_APPLE_TEAM_ID", "User"),
  [string]$Scheme = "ListenSDR",
  [string]$ProjectPath = "native-ios/ListenSDR.xcodeproj",
  [string]$BundleId = "com.kazek.sdr",
  [ValidateSet("login", "temporary-p12")]
  [string]$SigningMode = "login",
  [string]$RemoteLoginKeychainPassword = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD", "User"),
  [string]$RemoteDistributionP12Path = "~/EXPORT_FOR_KAZEK/Apple_Distribution_Mieczysaw_Bk_9N975WV782_AxelPong.p12",
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [switch]$UploadToTestFlight,
  [switch]$WaitForTestFlightProcessing,
  [int]$StatusPollIntervalSeconds = 10,
  [int]$StatusTimeoutMinutes = 20
)

$ErrorActionPreference = "Stop"

function Assert-LocalFile {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
    throw "$Label not found: $Path"
  }
}

function Get-LocalBuildVersion {
  param([string]$RepoPath)

  $infoPlistPath = Join-Path $RepoPath "native-ios\ListenSDR\Info.plist"
  if (-not (Test-Path $infoPlistPath)) {
    throw "Info.plist not found: $infoPlistPath"
  }

  $content = Get-Content $infoPlistPath -Raw
  $match = [regex]::Match($content, '<key>CFBundleVersion</key>\s*<string>([^<]+)</string>')
  if (-not $match.Success) {
    throw "Unable to read CFBundleVersion from Info.plist."
  }

  return $match.Groups[1].Value.Trim()
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

function ConvertTo-BashSingleQuotedLiteral {
  param([string]$Value)

  if ($null -eq $Value) {
    return "''"
  }

  $bashSingleQuoteEscape = "'" + '"' + "'" + '"' + "'"
  return "'" + ($Value -replace "'", $bashSingleQuoteEscape) + "'"
}

function Write-UnixTextFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $normalizedContent = ($Content -replace "`r`n", "`n") -replace "`r", "`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $normalizedContent, $utf8NoBom)
}

function Test-IncludedSnapshotPath {
  param([string]$RelativePath)

  $normalized = ($RelativePath -replace '\\', '/').TrimStart('./')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return $false
  }

  $excludePatterns = @(
    '(^|/)\.git($|/)',
    '(^|/)sideloadlydaemon\.log$',
    '(^|/)Listen-SDR-unsigned-local-.*\.ipa$',
    '(^|/)native-ios-build-local-.*\.log$',
    '(^|/)native-ios/build-local',
    '(^|/)native-ios/build-log-filter-test',
    '(^|/)native-ios/unsigned-ipa',
    '(^|/)server/listen-sdr-feedback-bot/__pycache__($|/)',
    '(^|/)\.expo($|/)',
    '(^|/).+\.xcresult($|/)'
  )

  foreach ($pattern in $excludePatterns) {
    if ($normalized -match $pattern) {
      return $false
    }
  }

  return $true
}

function Get-SnapshotPaths {
  param([string]$RepositoryPath)

  $tracked = @(& git -C $RepositoryPath ls-files)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to list tracked files."
  }

  $untracked = @(& git -C $RepositoryPath ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to list untracked files."
  }

  $allPaths = @($tracked + $untracked |
    ForEach-Object { if ($null -eq $_) { "" } else { "$_".Trim() } } |
    Where-Object { Test-IncludedSnapshotPath -RelativePath $_ } |
    Where-Object { Test-Path (Join-Path $RepositoryPath $_) } |
    Sort-Object -Unique)

  if ($allPaths.Count -eq 0) {
    throw "No files selected for remote snapshot."
  }

  return $allPaths
}

function New-RepoSnapshotArchive {
  param(
    [string]$RepositoryPath,
    [string[]]$SnapshotPaths
  )

  $tempRoot = Join-Path $env:TEMP "listen-sdr-remote-testflight"
  New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $archivePath = Join-Path $tempRoot ("listen-sdr-testflight-" + $stamp + ".tar.gz")
  $fileListPath = Join-Path $tempRoot ("listen-sdr-testflight-" + $stamp + ".files.txt")

  if (Test-Path $archivePath) {
    Remove-Item $archivePath -Force
  }

  Set-Content -Path $fileListPath -Value $SnapshotPaths -Encoding ascii

  Push-Location $RepositoryPath
  try {
    & tar -czf $archivePath -T $fileListPath
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to create repository snapshot archive."
    }
  } finally {
    Pop-Location
  }

  return @{
    ArchivePath = $archivePath
    FileListPath = $fileListPath
  }
}

Assert-LocalFile -Path $AscApiKeyPath -Label "ASC API key"

if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
  throw "ASC key ID or issuer ID is missing."
}
if ([string]::IsNullOrWhiteSpace($AppleTeamId)) {
  throw "Apple team ID is missing."
}
if ([string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
  $RemoteLoginKeychainPassword = Read-ListenSDRSecret -SecretName "remote-login-keychain-password"
}
if ($SigningMode -eq "temporary-p12" -and [string]::IsNullOrWhiteSpace($RemoteDistributionP12Password)) {
  throw "Remote distribution .p12 password is missing. Set LISTENSDR_REMOTE_P12_PASSWORD in user environment."
}
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "ssh is not available in PATH."
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
  throw "scp is not available in PATH."
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  throw "python is not available in PATH."
}
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
  throw "tar is not available in PATH."
}

$status = @(& git -C $RepoRoot status --short | Where-Object {
    $_ -notmatch 'sideloadlydaemon\.log$' -and
    $_ -notmatch '^\s*[MADRCU?]{1,2}\s+scripts/Run-ListenSDR-RemoteTestFlight\.ps1$'
  })
if ($status.Count -gt 0) {
  throw "Repository has unrelated uncommitted changes. Commit or stash them before remote TestFlight build."
}

$remoteHome = (ssh $RemoteHost 'printf %s "$HOME"').Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteHome)) {
  throw "Unable to resolve remote home directory."
}

$remoteRepoDirAbsolute = if ($RemoteRepoDir -eq "~") {
  $remoteHome
} elseif ($RemoteRepoDir -like "~/*") {
  ($remoteHome.TrimEnd('/') + '/' + $RemoteRepoDir.Substring(2))
} else {
  $RemoteRepoDir
}

$remoteRepoDirExpanded = if ($RemoteRepoDir -eq "~") {
  '$HOME'
} elseif ($RemoteRepoDir -like "~/*") {
  '$HOME/' + $RemoteRepoDir.Substring(2)
} else {
  $RemoteRepoDir
}

$remoteCiDir = "$remoteHome/.listen-sdr-ci"
$remoteBuildDir = "$remoteHome/.listen-sdr-build"
$remoteKeyPath = "$remoteCiDir/" + [System.IO.Path]::GetFileName($AscApiKeyPath)
$remoteProfilePath = "$remoteCiDir/ListenSDR_AppStore.mobileprovision"
$remoteRunnerPath = "$remoteCiDir/run-testflight.sh"
$remoteArchivePath = "$remoteCiDir/source.tar.gz"
$remoteSourceDir = "$remoteHome/.listen-sdr-src"
$remoteSourceStagingDir = "$remoteHome/.listen-sdr-src.new"

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path
$snapshotPaths = Get-SnapshotPaths -RepositoryPath $resolvedRepoRoot
$snapshot = New-RepoSnapshotArchive -RepositoryPath $resolvedRepoRoot -SnapshotPaths $snapshotPaths

Write-Host ""
Write-Host "==> Prepare remote directories"
ssh $RemoteHost "mkdir -p $remoteCiDir"
if ($LASTEXITCODE -ne 0) {
  throw "Unable to prepare remote directories."
}

Write-Host ""
Write-Host "==> Upload App Store Connect API key to remote Mac"
scp $AscApiKeyPath "${RemoteHost}:$remoteKeyPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload ASC API key."
}

Write-Host ""
Write-Host "==> Ensure App Store provisioning profile for $BundleId"
$profileScriptPath = Join-Path $PSScriptRoot "Ensure-ListenSDR-AppStoreProfile.ps1"
$profileJson = powershell -ExecutionPolicy Bypass -File $profileScriptPath `
  -BundleId $BundleId `
  -ProfileOutputPath (Join-Path $env:TEMP "ListenSDR_AppStore.mobileprovision") `
  -AscApiKeyPath $AscApiKeyPath `
  -AscKeyId $AscKeyId `
  -AscIssuerId $AscIssuerId
if ($LASTEXITCODE -ne 0) {
  throw "Unable to ensure provisioning profile."
}
$profileInfo = $profileJson | ConvertFrom-Json

Write-Host ""
Write-Host "==> Upload App Store provisioning profile to remote Mac"
scp $profileInfo.profilePath "${RemoteHost}:$remoteProfilePath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload provisioning profile."
}

Write-Host ""
Write-Host "==> Upload local source snapshot to remote Mac"
scp $snapshot.ArchivePath "${RemoteHost}:$remoteArchivePath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload source snapshot."
}

$remoteDistributionP12PathExpanded = if ($RemoteDistributionP12Path -eq "~") {
  '$HOME'
} elseif ($RemoteDistributionP12Path -like "~/*") {
  '$HOME/' + $RemoteDistributionP12Path.Substring(2)
} else {
  $RemoteDistributionP12Path
}

$uploadFlag = if ($UploadToTestFlight) { "true" } else { "false" }
$distP12PasswordValue = if ($SigningMode -eq "temporary-p12") { $RemoteDistributionP12Password } else { "" }
$remoteScriptTemplate = @'
set -euo pipefail
REPO_DIR=__REPO_DIR__
ARCHIVE_PATH=__ARCHIVE_PATH__
STAGING_DIR=__STAGING_DIR__
CI_ROOT=__CI_ROOT__
BUILD_ROOT=__BUILD_ROOT__
KEY_PATH=__KEY_PATH__
PROJECT_PATH=__PROJECT_PATH__
SCHEME=__SCHEME__
BUNDLE_ID=__BUNDLE_ID__
TEAM_ID=__TEAM_ID__
ASC_KEY_ID=__ASC_KEY_ID__
ASC_ISSUER_ID=__ASC_ISSUER_ID__
PROFILE_PATH=__PROFILE_PATH__
PROFILE_UUID=__PROFILE_UUID__
PROFILE_NAME=__PROFILE_NAME__
SIGNING_MODE=__SIGNING_MODE__
DIST_P12_PATH=__DIST_P12_PATH__
DIST_P12_PASSWORD=__DIST_P12_PASSWORD__
UPLOAD_TO_TESTFLIGHT=__UPLOAD_TO_TESTFLIGHT__
LOGIN_KEYCHAIN_PASSWORD="${LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD:-}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p "$CI_ROOT"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR"
rm -rf "$REPO_DIR"
mv "$STAGING_DIR" "$REPO_DIR"

cd "$REPO_DIR"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/export"

ARCHIVE_PATH="$BUILD_ROOT/ListenSDR.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
LOG_ARCHIVE="$BUILD_ROOT/xcodebuild-archive.log"
LOG_EXPORT="$BUILD_ROOT/xcodebuild-export.log"
LOG_UPLOAD="$BUILD_ROOT/testflight-upload.log"
TEMP_KEYCHAIN="$BUILD_ROOT/listensdr-testflight.keychain-db"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
ORIGINAL_DEFAULT_KEYCHAIN=$(security default-keychain -d user | tr -d '"')
ORIGINAL_KEYCHAINS=()
while IFS= read -r keychain_path; do
  ORIGINAL_KEYCHAINS+=("$keychain_path")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*//' | tr -d '"')

cleanup_keychain() {
  if [ -n "${ORIGINAL_DEFAULT_KEYCHAIN:-}" ]; then
    security default-keychain -d user -s "$ORIGINAL_DEFAULT_KEYCHAIN" >/dev/null 2>&1 || true
  fi

  if [ "${#ORIGINAL_KEYCHAINS[@]}" -gt 0 ]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  else
    security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "/Library/Keychains/System.keychain" >/dev/null 2>&1 || true
  fi

  if [ "$SIGNING_MODE" = "temporary-p12" ]; then
    security delete-keychain "$TEMP_KEYCHAIN" >/dev/null 2>&1 || true
  fi
}

trap cleanup_keychain EXIT

filter_known_xcodebuild_noise() {
  awk '
    BEGIN { skip = 0 }
    /DTDKRemoteDeviceConnection: Failed to start remote service "com\.apple\.mobile\.notification_proxy" on device\./ {
      skip = 1
      next
    }
    skip {
      if ($0 ~ /NSLocalizedDescription=Failed to start remote service "com\.apple\.mobile\.notification_proxy" on device\.\}/) {
        skip = 0
      }
      next
    }
    { print }
  '
}

run_xcodebuild_logged() {
  local log_path="$1"
  shift

  set +e
  "$@" 2>&1 | filter_known_xcodebuild_noise | tee "$log_path"
  local statuses=("${PIPESTATUS[@]}")
  set -e

  if [ "${statuses[0]}" -ne 0 ]; then
    return "${statuses[0]}"
  fi
  if [ "${statuses[1]}" -ne 0 ]; then
    return "${statuses[1]}"
  fi
  return "${statuses[2]}"
}

if command -v xcodegen >/dev/null 2>&1; then
  (cd native-ios && xcodegen generate)
fi

mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp "$PROFILE_PATH" "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision"

if security dump-trust-settings 2>/dev/null | grep -q "Apple Distribution:"; then
  echo "Remote Mac has custom user trust settings for Apple Distribution certificate."
  echo "Set that certificate trust back to system defaults in Keychain Access, then rerun."
  exit 2
fi

if [ "$SIGNING_MODE" = "login" ]; then
  security list-keychains -d user -s "$LOGIN_KEYCHAIN" "/Library/Keychains/System.keychain" >/dev/null
  security default-keychain -d user -s "$LOGIN_KEYCHAIN" >/dev/null

  if [ -n "$LOGIN_KEYCHAIN_PASSWORD" ]; then
    security unlock-keychain -p "$LOGIN_KEYCHAIN_PASSWORD" "$LOGIN_KEYCHAIN"
    security set-keychain-settings -lut 21600 "$LOGIN_KEYCHAIN"
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$LOGIN_KEYCHAIN_PASSWORD" "$LOGIN_KEYCHAIN" >/dev/null
  else
    echo "No explicit login keychain password provided; using existing login.keychain-db session." >&2
  fi

  if ! security find-identity -v -p codesigning "$LOGIN_KEYCHAIN" | grep -q "Apple Distribution:"; then
    echo "No Apple Distribution identity found in login.keychain-db." >&2
    echo "Import the distribution certificate into login.keychain-db or rerun with -SigningMode temporary-p12." >&2
    exit 3
  fi
  run_xcodebuild_logged "$LOG_ARCHIVE" \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    clean archive

  cat > "$BUILD_ROOT/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>$BUNDLE_ID</key>
    <string>$PROFILE_NAME</string>
  </dict>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF
else
  security delete-keychain "$TEMP_KEYCHAIN" >/dev/null 2>&1 || true
  security create-keychain -p "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN"
  security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
  security unlock-keychain -p "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN"
  security import "$DIST_P12_PATH" -k "$TEMP_KEYCHAIN" -P "$DIST_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild -T /usr/bin/productbuild >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$TEMP_KEYCHAIN" "$LOGIN_KEYCHAIN" "/Library/Keychains/System.keychain" >/dev/null
  security default-keychain -d user -s "$TEMP_KEYCHAIN" >/dev/null

  run_xcodebuild_logged "$LOG_ARCHIVE" \
    xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    clean archive

  cat > "$BUILD_ROOT/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF
fi

run_xcodebuild_logged "$LOG_EXPORT" \
  xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$BUILD_ROOT/exportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

IPA_PATH=$(find "$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -print -quit)
if [ -z "$IPA_PATH" ]; then
  echo "No IPA exported." >&2
  exit 1
fi

if [ "$UPLOAD_TO_TESTFLIGHT" = "true" ]; then
  set +e
  xcrun altool \
    --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" | tee "$LOG_UPLOAD"
  upload_status=${PIPESTATUS[0]}
  tee_status=${PIPESTATUS[1]}
  set -e

  if [ "$upload_status" -ne 0 ]; then
    exit "$upload_status"
  fi
  if [ "$tee_status" -ne 0 ]; then
    exit "$tee_status"
  fi
fi

printf 'IPA_PATH=%s\n' "$IPA_PATH"
printf 'ARCHIVE_LOG=%s\n' "$LOG_ARCHIVE"
printf 'EXPORT_LOG=%s\n' "$LOG_EXPORT"
printf 'UPLOAD_LOG=%s\n' "$LOG_UPLOAD"
'@

$remoteScript = $remoteScriptTemplate.
  Replace('__REPO_DIR__', $remoteRepoDirExpanded).
  Replace('__ARCHIVE_PATH__', $remoteArchivePath).
  Replace('__STAGING_DIR__', $remoteSourceStagingDir).
  Replace('__CI_ROOT__', $remoteCiDir).
  Replace('__BUILD_ROOT__', $remoteBuildDir).
  Replace('__KEY_PATH__', $remoteKeyPath).
  Replace('__PROJECT_PATH__', $ProjectPath).
  Replace('__SCHEME__', $Scheme).
  Replace('__BUNDLE_ID__', $BundleId).
  Replace('__TEAM_ID__', $AppleTeamId).
  Replace('__ASC_KEY_ID__', $AscKeyId).
  Replace('__ASC_ISSUER_ID__', $AscIssuerId).
  Replace('__PROFILE_PATH__', $remoteProfilePath).
  Replace('__PROFILE_UUID__', $profileInfo.profileUuid).
  Replace('__PROFILE_NAME__', $profileInfo.profileName).
  Replace('__SIGNING_MODE__', $SigningMode).
  Replace('__DIST_P12_PATH__', $remoteDistributionP12PathExpanded).
  Replace('__DIST_P12_PASSWORD__', $distP12PasswordValue).
  Replace('__UPLOAD_TO_TESTFLIGHT__', $uploadFlag)

Write-Host ""
Write-Host "==> Upload remote runner script"
$tempDir = Join-Path $env:TEMP "listen-sdr-remote-runner"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$localRunnerPath = Join-Path $tempDir "run-testflight.sh"
Write-UnixTextFile -Path $localRunnerPath -Content $remoteScript
scp $localRunnerPath "${RemoteHost}:$remoteRunnerPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload remote runner script."
}

Write-Host ""
Write-Host "==> Build on remote Mac"
$sshBuildCommand = "chmod +x $remoteRunnerPath && bash $remoteRunnerPath"
if ($SigningMode -eq "login" -and -not [string]::IsNullOrWhiteSpace($RemoteLoginKeychainPassword)) {
  $quotedLoginPassword = ConvertTo-BashSingleQuotedLiteral -Value $RemoteLoginKeychainPassword
  $sshBuildCommand = "chmod +x $remoteRunnerPath && LISTENSDR_REMOTE_LOGIN_KEYCHAIN_PASSWORD=$quotedLoginPassword bash $remoteRunnerPath"
}
$result = ssh $RemoteHost $sshBuildCommand
$exitCode = $LASTEXITCODE
$result | Write-Host
if ($exitCode -ne 0) {
  throw "Remote archive/export/upload failed."
}

if ($UploadToTestFlight -and $WaitForTestFlightProcessing) {
  $buildVersion = Get-LocalBuildVersion -RepoPath $RepoRoot
  $statusScriptPath = Join-Path $PSScriptRoot "Check-ListenSDR-TestFlightStatus.ps1"

  Write-Host ""
  Write-Host "==> Wait for TestFlight processing"
  & powershell -ExecutionPolicy Bypass -File $statusScriptPath `
    -BundleId $BundleId `
    -BuildVersion $buildVersion `
    -WaitUntilProcessed `
    -PollIntervalSeconds $StatusPollIntervalSeconds `
    -TimeoutMinutes $StatusTimeoutMinutes `
    -AscApiKeyPath $AscApiKeyPath `
    -AscKeyId $AscKeyId `
    -AscIssuerId $AscIssuerId

  if ($LASTEXITCODE -ne 0) {
    throw "TestFlight processing wait failed."
  }
}
