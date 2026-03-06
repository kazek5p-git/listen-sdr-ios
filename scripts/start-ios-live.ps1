param(
  [int]$WaitSeconds = 45
)

$ErrorActionPreference = "Stop"

function Get-ExpoUrl {
  try {
    $manifest = Invoke-RestMethod -Uri "http://localhost:8081" -TimeoutSec 5
    $hostUri = $manifest.extra.expoClient.hostUri
    if ($hostUri) {
      return "exp://$hostUri"
    }
  } catch {
  }
  return $null
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$expoDir = Join-Path $projectRoot ".expo"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outLog = Join-Path $expoDir "listen-sdr-dev-$stamp.out.log"
$errLog = Join-Path $expoDir "listen-sdr-dev-$stamp.err.log"

New-Item -ItemType Directory -Path $expoDir -Force | Out-Null

$existingUrl = Get-ExpoUrl
if ($existingUrl) {
  Write-Host "Expo dev server is already running."
  Write-Host "Open this in Expo Go on iPhone:"
  Write-Host "  $existingUrl"
  Set-Clipboard -Value $existingUrl
  Write-Host "Copied to clipboard."
  return
}

$proc = Start-Process `
  -FilePath "npx.cmd" `
  -ArgumentList @("expo", "start", "--tunnel") `
  -WorkingDirectory $projectRoot `
  -RedirectStandardOutput $outLog `
  -RedirectStandardError $errLog `
  -PassThru

Write-Host "Expo dev server started in background. PID: $($proc.Id)"
Write-Host "Logs:"
Write-Host "  $outLog"
Write-Host "  $errLog"

$url = $null
for ($i = 0; $i -lt $WaitSeconds; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $outLog) {
    $matches = Select-String -Path $outLog -Pattern "exp://[^\\s]+" -AllMatches -ErrorAction SilentlyContinue
    if ($matches) {
      $url = $matches[-1].Matches[-1].Value
      break
    }
  }
}

if (-not $url) {
  $url = Get-ExpoUrl
}

if ($url) {
  Write-Host ""
  Write-Host "Open this in Expo Go on iPhone:"
  Write-Host "  $url"
  Set-Clipboard -Value $url
  Write-Host "Copied to clipboard."
} else {
  Write-Host ""
  Write-Host "No exp:// URL detected yet. Check logs above and wait a bit longer."
}

Write-Host ""
Write-Host "To stop the dev server:"
Write-Host "  Stop-Process -Id $($proc.Id)"
