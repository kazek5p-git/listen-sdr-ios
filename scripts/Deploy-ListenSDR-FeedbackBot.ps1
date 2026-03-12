param(
  [Parameter(Mandatory = $true)]
  [string]$BotToken,

  [Parameter(Mandatory = $true)]
  [string]$OwnerUserId,

  [string]$AdditionalRecipientIds = "",

  [string]$RemoteUser = "kazek",
  [string]$RemoteHost = "kazpar.pl",
  [int]$RemotePort = 1024,
  [string]$RemoteKeyPath = "C:\Users\Kazek\.ssh\kazek",
  [int]$FeedbackPort = 18787
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$botScript = Join-Path $repoRoot "server\listen-sdr-feedback-bot\listen_sdr_feedback_bot.py"
$serviceFile = Join-Path $repoRoot "server\listen-sdr-feedback-bot\listen-sdr-feedback-bot.service"
$publicProxyFile = Join-Path $repoRoot "server\listen-sdr-feedback-bot\public\.htaccess"

if (-not (Test-Path $botScript)) {
  throw "Missing bot script: $botScript"
}

if (-not (Test-Path $serviceFile)) {
  throw "Missing service file: $serviceFile"
}

if (-not (Test-Path $publicProxyFile)) {
  throw "Missing Apache proxy file: $publicProxyFile"
}

$remote = "$RemoteUser@$RemoteHost"
$remoteHome = "/home/$RemoteUser"
$remoteAppDir = "$remoteHome/.local/share/listen-sdr-feedback-bot"
$remoteSystemdDir = "$remoteHome/.config/systemd/user"
$remoteEnvFile = "$remoteHome/.config/listen-sdr-feedback-bot.env"
$remoteServiceFile = "$remoteSystemdDir/listen-sdr-feedback-bot.service"
$remoteWebDir = "$remoteHome/www/listen-sdr-feedback"
$remoteProxyFile = "$remoteWebDir/.htaccess"

$envFile = New-TemporaryFile
try {
  $envLines = @(
    "LISTEN_SDR_BOT_TOKEN=$BotToken"
    "LISTEN_SDR_OWNER_ID=$OwnerUserId"
    "LISTEN_SDR_RECIPIENT_IDS=$OwnerUserId$(if ($AdditionalRecipientIds) { ",$AdditionalRecipientIds" })"
    "LISTEN_SDR_BIND_HOST=127.0.0.1"
    "LISTEN_SDR_PORT=$FeedbackPort"
  )
  $envContent = ($envLines -join "`n") + "`n"
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($envFile.FullName, $envContent, $utf8NoBom)

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "mkdir -p $remoteAppDir $remoteSystemdDir $remoteHome/.config $remoteWebDir"
  if ($LASTEXITCODE -ne 0) { throw "Failed to prepare remote directories." }

  & scp -i $RemoteKeyPath -P $RemotePort $botScript "${remote}:${remoteAppDir}/listen_sdr_feedback_bot.py"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload bot script." }

  & scp -i $RemoteKeyPath -P $RemotePort $serviceFile "${remote}:${remoteServiceFile}"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload service file." }

  & scp -i $RemoteKeyPath -P $RemotePort $envFile.FullName "${remote}:${remoteEnvFile}"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload environment file." }

  & scp -i $RemoteKeyPath -P $RemotePort $publicProxyFile "${remote}:${remoteProxyFile}"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload Apache proxy file." }

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "chmod 700 $remoteAppDir && chmod 600 $remoteEnvFile && chmod 644 $remoteServiceFile && chmod 644 $remoteProxyFile"
  if ($LASTEXITCODE -ne 0) { throw "Failed to set remote file permissions." }

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "systemctl --user daemon-reload"
  if ($LASTEXITCODE -ne 0) { throw "systemd daemon-reload failed." }

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "systemctl --user enable listen-sdr-feedback-bot.service"
  if ($LASTEXITCODE -ne 0) { throw "systemd enable failed." }

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "systemctl --user restart listen-sdr-feedback-bot.service"
  if ($LASTEXITCODE -ne 0) { throw "systemd restart failed." }

  Start-Sleep -Seconds 2

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "systemctl --user --no-pager --full status listen-sdr-feedback-bot.service"
  if ($LASTEXITCODE -ne 0) { throw "Remote service setup failed." }

  $null = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/getMe" -Method Get -TimeoutSec 20
  & ssh -i $RemoteKeyPath -p $RemotePort $remote "curl -fsS http://127.0.0.1:${FeedbackPort}/healthz"
  if ($LASTEXITCODE -ne 0) { throw "Remote health check failed." }

  $null = Invoke-RestMethod -Uri "https://$RemoteHost/listen-sdr-feedback/healthz" -Method Get -TimeoutSec 20

  Write-Host "Listen SDR feedback bot deployed successfully."
  Write-Host "Expected endpoint: https://$RemoteHost/listen-sdr-feedback/api/feedback"
} finally {
  Remove-Item $envFile.FullName -Force -ErrorAction SilentlyContinue
}
