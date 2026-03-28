param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRoot = "~/.listen-sdr-local",
  [string]$OutputIpaPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "Listen-SDR-unsigned-local-latest.ipa"),
  [switch]$DownloadBuildLog,
  [string]$LocalBuildLogPath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "native-ios-build-local-latest.log"),
  [switch]$InstallOnIPhone,
  [string]$SideloadlyBridgePath = "C:\Users\Kazek\Desktop\iOS\Install-IPA-Sideloadly-Bridge.ps1",
  [int]$InstallMaxAttempts = 3,
  [int]$InstallTimeoutSec = 180
)

$ErrorActionPreference = "Stop"

function Assert-Tool {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name is not available in PATH."
  }
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

function ConvertTo-BashSingleQuotedLiteral {
  param([string]$Value)

  if ($null -eq $Value) {
    return "''"
  }

  $bashSingleQuoteEscape = "'" + '"' + "'" + '"' + "'"
  return "'" + ($Value -replace "'", $bashSingleQuoteEscape) + "'"
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

  $tempRoot = Join-Path $env:TEMP "listen-sdr-remote-unsigned"
  New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $archivePath = Join-Path $tempRoot ("listen-sdr-unsigned-" + $stamp + ".tar.gz")
  $fileListPath = Join-Path $tempRoot ("listen-sdr-unsigned-" + $stamp + ".files.txt")

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

Assert-Tool -Name "git"
Assert-Tool -Name "ssh"
Assert-Tool -Name "scp"
Assert-Tool -Name "tar"

$resolvedRepoRoot = (Resolve-Path $RepoRoot).Path

$remoteHome = (ssh $RemoteHost 'printf %s "$HOME"').Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteHome)) {
  throw "Unable to resolve remote home directory."
}

$remoteRootAbsolute = if ($RemoteRoot -eq "~") {
  $remoteHome
} elseif ($RemoteRoot -like "~/*") {
  ($remoteHome.TrimEnd('/') + '/' + $RemoteRoot.Substring(2))
} else {
  $RemoteRoot
}

$snapshotPaths = Get-SnapshotPaths -RepositoryPath $resolvedRepoRoot
$snapshot = New-RepoSnapshotArchive -RepositoryPath $resolvedRepoRoot -SnapshotPaths $snapshotPaths

$remoteArchivePath = "$remoteRootAbsolute/source.tar.gz"
$remoteRunnerPath = "$remoteRootAbsolute/build-unsigned.sh"
$remoteSourceDir = "$remoteRootAbsolute/src"
$remoteStagingDir = "$remoteRootAbsolute/src.new"
$remoteBuildDir = "$remoteRootAbsolute/build"

$remoteScriptTemplate = @'
#!/bin/bash
set -euo pipefail

ROOT=__ROOT__
ARCHIVE_PATH=__ARCHIVE_PATH__
RUNNER_PATH=__RUNNER_PATH__
SOURCE_DIR=__SOURCE_DIR__
STAGING_DIR=__STAGING_DIR__
BUILD_DIR=__BUILD_DIR__
APP_DIR="$SOURCE_DIR/native-ios"
DERIVED_DATA_PATH="$BUILD_DIR/build-local-latest"
PACKAGE_ROOT="$BUILD_DIR/unsigned-ipa-local-latest"
IPA_PATH="$ROOT/Listen-SDR-unsigned-local-latest.ipa"
LOG_PATH="$ROOT/native-ios-build-local-latest.log"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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

mkdir -p "$ROOT"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$STAGING_DIR"
rm -rf "$SOURCE_DIR"
mv "$STAGING_DIR" "$SOURCE_DIR"

if command -v xcodegen >/dev/null 2>&1 && [ -f "$APP_DIR/project.yml" ]; then
  (cd "$APP_DIR" && xcodegen generate)
fi

rm -rf "$DERIVED_DATA_PATH" "$PACKAGE_ROOT" "$IPA_PATH" "$LOG_PATH"
mkdir -p "$PACKAGE_ROOT/Payload"

cd "$APP_DIR"
run_xcodebuild_logged "$LOG_PATH" \
  xcodebuild \
  -project ListenSDR.xcodeproj \
  -scheme ListenSDR \
  -configuration Release \
  -destination generic/platform=iOS \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_BUNDLE_PATH=$(find "$DERIVED_DATA_PATH/Build/Products/Release-iphoneos" -maxdepth 1 -type d -name "*.app" | head -n 1)
if [ -z "$APP_BUNDLE_PATH" ]; then
  echo "ERROR=app bundle not found"
  exit 1
fi

cp -R "$APP_BUNDLE_PATH" "$PACKAGE_ROOT/Payload/"
cd "$PACKAGE_ROOT"
/usr/bin/zip -qry "$IPA_PATH" Payload

if grep -nE 'notification_proxy|passcode protected|E800001A' "$LOG_PATH" >/dev/null; then
  echo "ERROR=known xcodebuild noise still present in log"
  exit 9
fi

INFO_PLIST="$APP_BUNDLE_PATH/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")
IPA_SIZE=$(/usr/bin/stat -f '%z' "$IPA_PATH")

printf 'IPA_PATH=%s\n' "$IPA_PATH"
printf 'LOG_PATH=%s\n' "$LOG_PATH"
printf 'VERSION=%s\n' "$VERSION"
printf 'BUILD=%s\n' "$BUILD"
printf 'IPA_SIZE=%s\n' "$IPA_SIZE"
printf 'NOISE_PRESENT=0\n'
'@

$remoteScript = $remoteScriptTemplate.
  Replace('__ROOT__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteRootAbsolute)).
  Replace('__ARCHIVE_PATH__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteArchivePath)).
  Replace('__RUNNER_PATH__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteRunnerPath)).
  Replace('__SOURCE_DIR__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteSourceDir)).
  Replace('__STAGING_DIR__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteStagingDir)).
  Replace('__BUILD_DIR__', (ConvertTo-BashSingleQuotedLiteral -Value $remoteBuildDir))

$tempRunnerPath = Join-Path $env:TEMP "build-listensdr-remote-unsigned.sh"
Write-UnixTextFile -Path $tempRunnerPath -Content $remoteScript

Write-Host ""
Write-Host "==> Prepare remote unsigned build workspace"
ssh $RemoteHost "mkdir -p $remoteRootAbsolute"
if ($LASTEXITCODE -ne 0) {
  throw "Unable to prepare remote workspace."
}

Write-Host ""
Write-Host "==> Upload current working tree snapshot"
scp $snapshot.ArchivePath "${RemoteHost}:$remoteArchivePath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload repository snapshot."
}

Write-Host ""
Write-Host "==> Upload remote unsigned build runner"
scp $tempRunnerPath "${RemoteHost}:$remoteRunnerPath" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to upload remote runner."
}

Write-Host ""
Write-Host "==> Build unsigned IPA on remote Mac"
$remoteResult = ssh $RemoteHost "chmod +x $remoteRunnerPath && $remoteRunnerPath"
if ($LASTEXITCODE -ne 0) {
  throw "Remote unsigned build failed."
}

$resultMap = @{}
foreach ($line in @($remoteResult)) {
  if ($line -match '^([A-Z_]+)=(.*)$') {
    $resultMap[$matches[1]] = $matches[2]
  }
}

if (-not $resultMap.ContainsKey("IPA_PATH")) {
  throw "Remote build did not return IPA_PATH."
}
if (-not $resultMap.ContainsKey("VERSION") -or -not $resultMap.ContainsKey("BUILD")) {
  throw "Remote build did not return version metadata."
}
if ($resultMap["NOISE_PRESENT"] -ne "0") {
  throw "Remote build log still contains filtered Xcode noise."
}

$outputIpaDirectory = Split-Path -Parent $OutputIpaPath
if (-not [string]::IsNullOrWhiteSpace($outputIpaDirectory)) {
  New-Item -ItemType Directory -Path $outputIpaDirectory -Force | Out-Null
}

Write-Host ""
Write-Host "==> Download unsigned IPA"
scp "${RemoteHost}:$($resultMap['IPA_PATH'])" $OutputIpaPath | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Unable to download unsigned IPA."
}

if ($DownloadBuildLog) {
  $localLogDirectory = Split-Path -Parent $LocalBuildLogPath
  if (-not [string]::IsNullOrWhiteSpace($localLogDirectory)) {
    New-Item -ItemType Directory -Path $localLogDirectory -Force | Out-Null
  }

  Write-Host ""
  Write-Host "==> Download remote build log"
  scp "${RemoteHost}:$($resultMap['LOG_PATH'])" $LocalBuildLogPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to download build log."
  }
}

if ($InstallOnIPhone) {
  if (-not (Test-Path $SideloadlyBridgePath)) {
    throw "Sideloadly bridge not found: $SideloadlyBridgePath"
  }

  Write-Host ""
  Write-Host "==> Install IPA on iPhone"
  & powershell -ExecutionPolicy Bypass -File $SideloadlyBridgePath -IpaPath $OutputIpaPath -MaxAttempts $InstallMaxAttempts -TimeoutSec $InstallTimeoutSec
  if ($LASTEXITCODE -ne 0) {
    throw "IPA installation failed."
  }
}

Write-Host ""
Write-Host ("IPA: " + $OutputIpaPath)
Write-Host ("Version: " + $resultMap["VERSION"] + " (" + $resultMap["BUILD"] + ")")
Write-Host ("Remote log: " + $resultMap["LOG_PATH"])
if ($DownloadBuildLog) {
  Write-Host ("Local log: " + $LocalBuildLogPath)
}
Write-Host "Known Xcode device-noise filter: clean"
