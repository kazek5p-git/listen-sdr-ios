param(
  [string]$CommitMessage,
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$DesktopRoot = "C:\Users\Kazek\Desktop\iOS",
  [int]$WorkflowTimeoutSec = 1800,
  [int]$PollIntervalSec = 10,
  [int]$InstallTimeoutSec = 180,
  [switch]$SkipCommit,
  [switch]$SkipInstall,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$unsignedWorkflowName = "iOS Unsigned IPA (Native)"
$syncWorkflowName = "Sync Generated Xcode Project"
$ignoredLocalFiles = @("sideloadlydaemon.log")

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host ("==> " + $Message)
}

function Invoke-Git {
  param([string[]]$Arguments)
  & git -C $RepoRoot @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git failed: $($Arguments -join ' ')"
  }
}

function Invoke-Gh {
  param([string[]]$Arguments)
  Push-Location $RepoRoot
  try {
    & gh @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "gh failed: $($Arguments -join ' ')"
    }
  } finally {
    Pop-Location
  }
}

function Assert-Tooling {
  foreach ($tool in @("git", "gh", "python")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "Required tool not found in PATH: $tool"
    }
  }
}

function Get-CurrentBranch {
  $branch = (& git -C $RepoRoot branch --show-current).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine current branch."
  }
  return $branch
}

function Get-RelevantStatusLines {
  $lines = @(& git -C $RepoRoot status --short)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read git status."
  }
  return @($lines | Where-Object {
      $line = $_.TrimEnd()
      foreach ($ignored in $ignoredLocalFiles) {
        if ($line -match ([regex]::Escape($ignored) + "$")) {
          return $false
        }
      }
      return $true
    })
}

function Show-PreflightChecklist {
  Write-Step "Preflight GitHub checklist"
  Write-Host "1. Scope pusha ma byc czysty i zgodny z aktualna zmiana."
  Write-Host "2. README nie moze zawierac niezatwierdzonych planow."
  Write-Host "3. Push ma obejmowac tylko realnie wdrozone zmiany."

  $statusLines = Get-RelevantStatusLines
  $readmeChanges = @($statusLines | Where-Object { $_ -match 'README\.md$' })
  Write-Host ("Branch: " + (Get-CurrentBranch))
  Write-Host ("README changed: " + ($(if ($readmeChanges.Count -gt 0) { "yes" } else { "no" })))
  Write-Host ("Relevant working tree changes: " + $statusLines.Count)
}

function Stage-RelevantChanges {
  Invoke-Git @("add", "-u", "--", ".")

  $untracked = @(& git -C $RepoRoot ls-files --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to read untracked files."
  }

  $untrackedToAdd = @($untracked | Where-Object {
      $path = $_.Trim()
      foreach ($ignored in $ignoredLocalFiles) {
        if ($path -match ("(^|[\\/])" + [regex]::Escape($ignored) + "$")) {
          return $false
        }
      }
      return -not [string]::IsNullOrWhiteSpace($path)
    })

  if ($untrackedToAdd.Count -gt 0) {
    $gitArgs = @("add", "--") + $untrackedToAdd
    Invoke-Git -Arguments $gitArgs
  }
}

function Has-StagedChanges {
  & git -C $RepoRoot diff --cached --quiet --
  return ($LASTEXITCODE -ne 0)
}

function Commit-IfNeeded {
  if ($SkipCommit) {
    Write-Host "Commit step skipped by flag."
    return
  }

  Stage-RelevantChanges

  if (-not (Has-StagedChanges)) {
    Write-Host "No staged changes to commit."
    return
  }

  if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
    throw "Commit message is required when there are changes to commit."
  }

  Write-Step "Commit changes"
  Invoke-Git @("commit", "-m", $CommitMessage)
}

function Push-Main {
  Write-Step "Push main"
  Invoke-Git @("push", "origin", "main")
}

function Get-HeadSha {
  $sha = (& git -C $RepoRoot rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sha)) {
    throw "Unable to determine HEAD SHA."
  }
  return $sha
}

function Wait-WorkflowCompletion {
  param(
    [string]$CommitSha,
    [string]$WorkflowName
  )

  $deadline = (Get-Date).AddSeconds($WorkflowTimeoutSec)
  $run = $null

  while ((Get-Date) -lt $deadline) {
    $json = Invoke-Gh @("run", "list", "--commit", $CommitSha, "--limit", "20", "--json", "databaseId,workflowName,headSha,status,conclusion,url,displayTitle")
    $runs = @(($json -join [Environment]::NewLine) | ConvertFrom-Json)
    $run = $runs |
      Where-Object { $_.headSha -eq $CommitSha -and $_.workflowName -eq $WorkflowName } |
      Sort-Object databaseId -Descending |
      Select-Object -First 1

    if ($run) {
      if ($run.status -eq "completed") {
        return $run
      }
      Write-Host ("Waiting for " + $WorkflowName + " run " + $run.databaseId + " (" + $run.status + ")")
    } else {
      Write-Host ("Waiting for workflow to appear: " + $WorkflowName)
    }

    Start-Sleep -Seconds $PollIntervalSec
  }

  throw "Timed out waiting for workflow: $WorkflowName"
}

function FastForward-MainIfNeeded {
  Write-Step "Sync local main"
  Invoke-Git @("fetch", "origin")
  $localHead = (& git -C $RepoRoot rev-parse HEAD).Trim()
  $remoteHead = (& git -C $RepoRoot rev-parse origin/main).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to compare local and origin/main."
  }

  if ($localHead -ne $remoteHead) {
    Invoke-Git @("pull", "--ff-only", "origin", "main")
  } else {
    Write-Host "Local main already matches origin/main."
  }
}

function Download-UnsignedIpa {
  param([int]$RunId)

  Write-Step "Download IPA artifact"
  $downloadDir = Join-Path $DesktopRoot ("build_" + $RunId + "_download")
  if (Test-Path $downloadDir) {
    Remove-Item $downloadDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  Invoke-Gh @("run", "download", $RunId, "-D", $downloadDir)

  $ipa = Get-ChildItem -Path $downloadDir -Recurse -Filter "*.ipa" -File | Select-Object -First 1
  if ($null -eq $ipa) {
    throw "Downloaded workflow does not contain an IPA."
  }

  return $ipa.FullName
}

function Get-IpaMetadata {
  param([string]$IpaPath)

  $py = @"
import pathlib
import plistlib
import zipfile

ipa = pathlib.Path(r'''$IpaPath''')
with zipfile.ZipFile(ipa, "r") as zf:
    plist_name = next(name for name in zf.namelist() if name.startswith("Payload/") and name.endswith("Info.plist"))
    data = plistlib.loads(zf.read(plist_name))
    print(data.get("CFBundleIdentifier", ""))
    print(data.get("CFBundleShortVersionString", ""))
    print(data.get("CFBundleVersion", ""))
"@
  $lines = @($py | python -)
  if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 3) {
    throw "Unable to read IPA metadata."
  }
  [pscustomobject]@{
    BundleId = $lines[0].Trim()
    Version = $lines[1].Trim()
    Build = $lines[2].Trim()
  }
}

function Install-Ipa {
  param([string]$IpaPath)

  if ($SkipInstall) {
    Write-Host "Install step skipped by flag."
    return $null
  }

  $bridgePath = Join-Path $DesktopRoot "Install-IPA-Sideloadly-Bridge.ps1"
  if (-not (Test-Path $bridgePath)) {
    throw "Bridge script not found: $bridgePath"
  }

  Write-Step "Install IPA on iPhone"
  & powershell -ExecutionPolicy Bypass -File $bridgePath -IpaPath $IpaPath -MaxAttempts 3 -TimeoutSec $InstallTimeoutSec
  if ($LASTEXITCODE -ne 0) {
    throw "IPA installation failed."
  }
}

Assert-Tooling

$branch = Get-CurrentBranch
if ($branch -ne "main") {
  throw "This pipeline is standardized for branch 'main'. Current branch: $branch"
}

Show-PreflightChecklist
if ($DryRun) {
  Write-Step "Dry run"
  Write-Host "Dry run requested. Pipeline stopped before commit/push."
  exit 0
}

Commit-IfNeeded
Push-Main

$headSha = Get-HeadSha
Write-Step "Wait for GitHub Actions"
$unsignedRun = Wait-WorkflowCompletion -CommitSha $headSha -WorkflowName $unsignedWorkflowName
$syncRun = Wait-WorkflowCompletion -CommitSha $headSha -WorkflowName $syncWorkflowName

if ($unsignedRun.conclusion -ne "success") {
  throw "Unsigned IPA workflow failed: $($unsignedRun.url)"
}
if ($syncRun.conclusion -ne "success") {
  throw "Sync xcodeproj workflow failed: $($syncRun.url)"
}

FastForward-MainIfNeeded

$ipaPath = Download-UnsignedIpa -RunId $unsignedRun.databaseId
$ipaMetadata = Get-IpaMetadata -IpaPath $ipaPath

Write-Step "IPA verification"
Write-Host ("IPA: " + $ipaPath)
Write-Host ("Bundle ID: " + $ipaMetadata.BundleId)
Write-Host ("Version: " + $ipaMetadata.Version)
Write-Host ("Build: " + $ipaMetadata.Build)

Install-Ipa -IpaPath $ipaPath

Write-Step "Pipeline summary"
Write-Host ("Commit SHA: " + $headSha)
Write-Host ("Unsigned IPA run: " + $unsignedRun.databaseId)
Write-Host ("Sync run: " + $syncRun.databaseId)
Write-Host ("IPA path: " + $ipaPath)
