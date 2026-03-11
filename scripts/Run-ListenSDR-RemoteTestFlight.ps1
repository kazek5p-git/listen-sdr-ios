param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRoot = "~/listen-sdr-remote",
  [string]$AscApiKeyPath = "C:\Users\Kazek\Desktop\Mac i logowanie\AuthKey_RDRPTFY7U4.p8",
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$AppleTeamId = [Environment]::GetEnvironmentVariable("EXPO_APPLE_TEAM_ID", "User"),
  [string]$Scheme = "ListenSDR",
  [string]$ProjectPath = "native-ios/ListenSDR.xcodeproj",
  [switch]$UploadToTestFlight,
  [switch]$SkipDirtyCheck
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

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Sync-ListenSDR-ToMac.ps1") -RepoRoot $RepoRoot -RemoteHost $RemoteHost -RemoteRoot $RemoteRoot @($(if ($SkipDirtyCheck) { "-SkipDirtyCheck" }))
if ($LASTEXITCODE -ne 0) {
  throw "Remote sync failed."
}

$remoteCiDir = "$RemoteRoot/ci"
$remoteBuildDir = "$RemoteRoot/build"
$remoteKeyPath = "$remoteCiDir/" + [System.IO.Path]::GetFileName($AscApiKeyPath)

Write-Host ""
Write-Host "==> Upload App Store Connect API key to remote Mac"
ssh $RemoteHost "mkdir -p $remoteCiDir $remoteBuildDir"
if ($LASTEXITCODE -ne 0) {
  throw "Unable to prepare remote CI directory."
}
scp $AscApiKeyPath "${RemoteHost}:$remoteKeyPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload ASC API key."
}

$uploadFlag = if ($UploadToTestFlight) { "true" } else { "false" }
$remoteScript = @"
set -euo pipefail
SRC_ROOT=$RemoteRoot/src
CI_ROOT=$remoteCiDir
BUILD_ROOT=$remoteBuildDir
KEY_PATH=$remoteKeyPath
PROJECT_PATH=$ProjectPath
SCHEME=$Scheme
TEAM_ID=$AppleTeamId
ASC_KEY_ID=$AscKeyId
ASC_ISSUER_ID=$AscIssuerId
UPLOAD_TO_TESTFLIGHT=$uploadFlag

cd "\$SRC_ROOT"

rm -rf "\$BUILD_ROOT"
mkdir -p "\$BUILD_ROOT/export"

ARCHIVE_PATH="\$BUILD_ROOT/ListenSDR.xcarchive"
EXPORT_PATH="\$BUILD_ROOT/export"
LOG_ARCHIVE="\$BUILD_ROOT/xcodebuild-archive.log"
LOG_EXPORT="\$BUILD_ROOT/xcodebuild-export.log"
LOG_UPLOAD="\$BUILD_ROOT/testflight-upload.log"

if command -v xcodegen >/dev/null 2>&1; then
  (cd native-ios && xcodegen generate)
fi

xcodebuild \
  -project "\$PROJECT_PATH" \
  -scheme "\$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "\$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "\$KEY_PATH" \
  -authenticationKeyID "\$ASC_KEY_ID" \
  -authenticationKeyIssuerID "\$ASC_ISSUER_ID" \
  DEVELOPMENT_TEAM="\$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER=com.kazek.sdr \
  clean archive | tee "\$LOG_ARCHIVE"

cat > "\$BUILD_ROOT/exportOptions.plist" <<EOF
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
  <string>\$TEAM_ID</string>
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
  -archivePath "\$ARCHIVE_PATH" \
  -exportPath "\$EXPORT_PATH" \
  -exportOptionsPlist "\$BUILD_ROOT/exportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "\$KEY_PATH" \
  -authenticationKeyID "\$ASC_KEY_ID" \
  -authenticationKeyIssuerID "\$ASC_ISSUER_ID" | tee "\$LOG_EXPORT"

IPA_PATH=\$(find "\$EXPORT_PATH" -maxdepth 1 -name "*.ipa" -print -quit)
if [ -z "\$IPA_PATH" ]; then
  echo "No IPA exported." >&2
  exit 1
fi

if [ "\$UPLOAD_TO_TESTFLIGHT" = "true" ]; then
  xcrun altool \
    --upload-app \
    --type ios \
    --file "\$IPA_PATH" \
    --apiKey "\$ASC_KEY_ID" \
    --apiIssuer "\$ASC_ISSUER_ID" | tee "\$LOG_UPLOAD"
fi

printf 'IPA_PATH=%s\n' "\$IPA_PATH"
printf 'ARCHIVE_LOG=%s\n' "\$LOG_ARCHIVE"
printf 'EXPORT_LOG=%s\n' "\$LOG_EXPORT"
printf 'UPLOAD_LOG=%s\n' "\$LOG_UPLOAD"
"@

Write-Host ""
Write-Host "==> Build on remote Mac"
$result = ssh $RemoteHost "bash -lc '$remoteScript'"
$exitCode = $LASTEXITCODE
$result | Write-Host
if ($exitCode -ne 0) {
  throw "Remote archive/export/upload failed."
}
