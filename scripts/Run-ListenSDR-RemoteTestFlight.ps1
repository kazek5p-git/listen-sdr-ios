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
  [string]$RemoteDistributionP12Path = "~/EXPORT_FOR_KAZEK/Apple_Distribution_Mieczysaw_Bk_9N975WV782_AxelPong.p12",
  [string]$RemoteDistributionP12Password = [Environment]::GetEnvironmentVariable("LISTENSDR_REMOTE_P12_PASSWORD", "User"),
  [switch]$UploadToTestFlight
)

$ErrorActionPreference = "Stop"

function Assert-LocalFile {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
    throw "$Label not found: $Path"
  }
}

Assert-LocalFile -Path $AscApiKeyPath -Label "ASC API key"

if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
  throw "ASC key ID or issuer ID is missing."
}
if ([string]::IsNullOrWhiteSpace($AppleTeamId)) {
  throw "Apple team ID is missing."
}
if ([string]::IsNullOrWhiteSpace($RemoteDistributionP12Password)) {
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

$remoteDistributionP12PathExpanded = if ($RemoteDistributionP12Path -eq "~") {
  '$HOME'
} elseif ($RemoteDistributionP12Path -like "~/*") {
  '$HOME/' + $RemoteDistributionP12Path.Substring(2)
} else {
  $RemoteDistributionP12Path
}

$uploadFlag = if ($UploadToTestFlight) { "true" } else { "false" }
$remoteScriptTemplate = @'
set -euo pipefail
REPO_DIR=__REPO_DIR__
REPO_URL=__REPO_URL__
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
DIST_P12_PATH=__DIST_P12_PATH__
DIST_P12_PASSWORD=__DIST_P12_PASSWORD__
UPLOAD_TO_TESTFLIGHT=__UPLOAD_TO_TESTFLIGHT__

if [ -d "$REPO_DIR" ] && [ ! -d "$REPO_DIR/.git" ]; then
  rm -rf "$REPO_DIR"
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"
git fetch origin
git checkout main
git reset --hard origin/main
git clean -fdx

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/export"

ARCHIVE_PATH="$BUILD_ROOT/ListenSDR.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
LOG_ARCHIVE="$BUILD_ROOT/xcodebuild-archive.log"
LOG_EXPORT="$BUILD_ROOT/xcodebuild-export.log"
LOG_UPLOAD="$BUILD_ROOT/testflight-upload.log"
TEMP_KEYCHAIN="$BUILD_ROOT/listensdr-testflight.keychain-db"

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

security delete-keychain "$TEMP_KEYCHAIN" >/dev/null 2>&1 || true
security create-keychain -p "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN"
security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN"
security unlock-keychain -p "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN"
security import "$DIST_P12_PATH" -k "$TEMP_KEYCHAIN" -P "$DIST_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild -T /usr/bin/productbuild >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$DIST_P12_PASSWORD" "$TEMP_KEYCHAIN" >/dev/null
security list-keychains -d user -s "$TEMP_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db" "/Library/Keychains/System.keychain" >/dev/null
security default-keychain -d user -s "$TEMP_KEYCHAIN" >/dev/null

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
  CODE_SIGN_IDENTITY="" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  clean archive | tee "$LOG_ARCHIVE"

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

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$BUILD_ROOT/exportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" | tee "$LOG_EXPORT"

IPA_PATH=$(find "$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -print -quit)
if [ -z "$IPA_PATH" ]; then
  echo "No IPA exported." >&2
  exit 1
fi

if [ "$UPLOAD_TO_TESTFLIGHT" = "true" ]; then
  xcrun altool \
    --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" | tee "$LOG_UPLOAD"
fi

printf 'IPA_PATH=%s\n' "$IPA_PATH"
printf 'ARCHIVE_LOG=%s\n' "$LOG_ARCHIVE"
printf 'EXPORT_LOG=%s\n' "$LOG_EXPORT"
printf 'UPLOAD_LOG=%s\n' "$LOG_UPLOAD"
'@

$remoteScript = $remoteScriptTemplate.
  Replace('__REPO_DIR__', $remoteRepoDirExpanded).
  Replace('__REPO_URL__', $RepoUrl).
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
  Replace('__DIST_P12_PATH__', $remoteDistributionP12PathExpanded).
  Replace('__DIST_P12_PASSWORD__', $RemoteDistributionP12Password).
  Replace('__UPLOAD_TO_TESTFLIGHT__', $uploadFlag)

Write-Host ""
Write-Host "==> Upload remote runner script"
$tempDir = Join-Path $env:TEMP "listen-sdr-remote-runner"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$localRunnerPath = Join-Path $tempDir "run-testflight.sh"
$remoteScriptUnix = $remoteScript -replace "`r`n", "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($localRunnerPath, $remoteScriptUnix, $utf8NoBom)
scp $localRunnerPath "${RemoteHost}:$remoteRunnerPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload remote runner script."
}

Write-Host ""
Write-Host "==> Build on remote Mac"
$result = ssh $RemoteHost "chmod +x $remoteRunnerPath && bash $remoteRunnerPath"
$exitCode = $LASTEXITCODE
$result | Write-Host
if ($exitCode -ne 0) {
  throw "Remote archive/export/upload failed."
}
