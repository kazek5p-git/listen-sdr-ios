param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$RepoSlug = "kazek5p-git/listen-sdr-ios",
  [string]$WorkflowFile = ".github/workflows/ios-signed-testflight.yml",
  [string]$DesktopRoot = "C:\Users\Kazek\Desktop\iOS",
  [switch]$UploadToTestFlight,
  [int]$WorkflowTimeoutSec = 3600,
  [int]$PollIntervalSec = 10
)

$ErrorActionPreference = "Stop"

function Invoke-GhInRepo {
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

function Write-Step {
  param([string]$Text)
  Write-Host ""
  Write-Host ("==> " + $Text)
}

function Get-HeadSha {
  $sha = (& git -C $RepoRoot rev-parse origin/main).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sha)) {
    throw "Unable to resolve origin/main SHA."
  }
  return $sha
}

function Wait-WorkflowRun {
  param(
    [string]$HeadSha,
    [string]$WorkflowName
  )

  $deadline = (Get-Date).AddSeconds($WorkflowTimeoutSec)

  while ((Get-Date) -lt $deadline) {
    $json = Invoke-GhInRepo @("run", "list", "--repo", $RepoSlug, "--commit", $HeadSha, "--limit", "20", "--json", "databaseId,workflowName,headSha,status,conclusion,url,displayTitle")
    $runs = @(((($json -join [Environment]::NewLine) | ConvertFrom-Json) | ForEach-Object { $_ }))
    $run = $runs |
      Where-Object { $_.headSha -eq $HeadSha -and $_.workflowName -eq $WorkflowName } |
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

function Download-RunArtifacts {
  param([long]$RunId)

  $downloadDir = Join-Path $DesktopRoot ("testflight_" + $RunId)
  if (Test-Path $downloadDir) {
    Remove-Item $downloadDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
  Invoke-GhInRepo @("run", "download", $RunId, "--repo", $RepoSlug, "-D", $downloadDir)
  return $downloadDir
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "gh is not available in PATH."
}

$dirty = @(& git -C $RepoRoot status --short | Where-Object { $_ -notmatch 'sideloadlydaemon\.log$' })
if ($dirty.Count -gt 0) {
  throw "Repository has uncommitted changes. Publish current code first, then run TestFlight."
}

Write-Step "Trigger signed TestFlight workflow"
$inputValue = if ($UploadToTestFlight) { "true" } else { "false" }
Invoke-GhInRepo @("workflow", "run", $WorkflowFile, "--repo", $RepoSlug, "-f", "upload_to_testflight=$inputValue")

$headSha = Get-HeadSha
Write-Step "Wait for workflow completion"
$run = Wait-WorkflowRun -HeadSha $headSha -WorkflowName "iOS Signed IPA + TestFlight (Native)"

if ($run.conclusion -ne "success") {
  Write-Host ("Workflow failed: " + $run.url)
  throw "Signed TestFlight workflow failed."
}

Write-Step "Download artifacts"
$downloadDir = Download-RunArtifacts -RunId ([long]$run.databaseId)

Write-Host ""
Write-Host ("Run URL: " + $run.url)
Write-Host ("Artifacts: " + $downloadDir)
Write-Host ("Upload to TestFlight: " + $inputValue)
