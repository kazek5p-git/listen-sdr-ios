param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RemoteHost = "mac_axela",
  [string]$RemoteRoot = "~/listen-sdr-remote",
  [switch]$SkipDirtyCheck
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
  param([string[]]$Arguments)
  & git -C $RepoRoot @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git failed: $($Arguments -join ' ')"
  }
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw "ssh is not available in PATH."
}
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
  throw "scp is not available in PATH."
}

$status = @(& git -C $RepoRoot status --short | Where-Object { $_ -notmatch 'sideloadlydaemon\.log$' })
if (-not $SkipDirtyCheck -and $status.Count -gt 0) {
  throw "Repository has uncommitted changes. Commit or stash them before remote sync."
}

$headSha = (& git -C $RepoRoot rev-parse --short=12 HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headSha)) {
  throw "Unable to resolve HEAD SHA."
}

$tempDir = Join-Path $env:TEMP "listen-sdr-remote-sync"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$archivePath = Join-Path $tempDir ("listen-sdr-" + $headSha + ".tar.gz")
if (Test-Path $archivePath) {
  Remove-Item $archivePath -Force
}

Write-Host ""
Write-Host "==> Create source archive"
Invoke-Git @("archive", "--format=tar.gz", "--output", $archivePath, "HEAD")

$remoteArchive = "$RemoteRoot/source.tar.gz"
$remoteStaging = "$RemoteRoot/src.new"
$remoteSource = "$RemoteRoot/src"

Write-Host ""
Write-Host "==> Prepare remote directories"
ssh $RemoteHost "mkdir -p $RemoteRoot"
if ($LASTEXITCODE -ne 0) {
  throw "Unable to create remote root."
}

Write-Host ""
Write-Host "==> Upload archive"
scp $archivePath "${RemoteHost}:$remoteArchive" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "scp upload failed."
}

Write-Host ""
Write-Host "==> Extract on remote Mac"
$remoteCmd = @"
set -euo pipefail
rm -rf $remoteStaging
mkdir -p $remoteStaging
tar -xzf $remoteArchive -C $remoteStaging
rm -rf $remoteSource
mv $remoteStaging $remoteSource
echo $remoteSource
"@
$resolvedRemoteSource = (ssh $RemoteHost "bash -lc '$remoteCmd'").Trim()
if ($LASTEXITCODE -ne 0) {
  throw "Remote extract failed."
}

Write-Host ""
Write-Host ("Remote source ready: " + $resolvedRemoteSource)
Write-Host ("Source commit: " + $headSha)
