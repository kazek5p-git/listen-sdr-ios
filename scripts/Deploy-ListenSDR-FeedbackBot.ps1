param(
  [Parameter(Mandatory = $true)]
  [string]$BotToken,

  [Parameter(Mandatory = $true)]
  [string]$OwnerUserId,

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

if (-not (Test-Path $botScript)) {
  throw "Missing bot script: $botScript"
}

if (-not (Test-Path $serviceFile)) {
  throw "Missing service file: $serviceFile"
}

$remote = "$RemoteUser@$RemoteHost"
$remoteAppDir = "~/.local/share/listen-sdr-feedback-bot"
$remoteSystemdDir = "~/.config/systemd/user"
$remoteEnvFile = "~/.config/listen-sdr-feedback-bot.env"
$remoteServiceFile = "$remoteSystemdDir/listen-sdr-feedback-bot.service"

$envFile = New-TemporaryFile
try {
  @(
    "LISTEN_SDR_BOT_TOKEN=$BotToken"
    "LISTEN_SDR_OWNER_ID=$OwnerUserId"
    "LISTEN_SDR_BIND_HOST=0.0.0.0"
    "LISTEN_SDR_PORT=$FeedbackPort"
  ) | Set-Content -Path $envFile.FullName -Encoding utf8

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "mkdir -p $remoteAppDir $remoteSystemdDir ~/.config"
  if ($LASTEXITCODE -ne 0) { throw "Failed to prepare remote directories." }

  & scp -i $RemoteKeyPath -P $RemotePort $botScript "${remote}:${remoteAppDir}/listen_sdr_feedback_bot.py"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload bot script." }

  & scp -i $RemoteKeyPath -P $RemotePort $serviceFile "${remote}:${remoteServiceFile}"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload service file." }

  & scp -i $RemoteKeyPath -P $RemotePort $envFile.FullName "${remote}:${remoteEnvFile}"
  if ($LASTEXITCODE -ne 0) { throw "Failed to upload environment file." }

  $remoteScript = @"
chmod 700 $remoteAppDir
chmod 600 $remoteEnvFile
chmod 644 $remoteServiceFile
systemctl --user daemon-reload
systemctl --user enable --now listen-sdr-feedback-bot.service
sleep 2
systemctl --user --no-pager --full status listen-sdr-feedback-bot.service
python3 - <<'PY'
import json, os, urllib.request
token = os.environ['LISTEN_SDR_BOT_TOKEN']
with urllib.request.urlopen(f'https://api.telegram.org/bot{token}/getMe', timeout=10) as response:
    payload = json.load(response)
    print(json.dumps(payload, ensure_ascii=False))
PY
curl -fsS http://127.0.0.1:$FeedbackPort/healthz
"@

  & ssh -i $RemoteKeyPath -p $RemotePort $remote "env $(cat $remoteEnvFile | xargs) bash -lc '$remoteScript'"
  if ($LASTEXITCODE -ne 0) { throw "Remote service setup failed." }

  Write-Host "Listen SDR feedback bot deployed successfully."
  Write-Host "Expected endpoint: http://$RemoteHost`:$FeedbackPort/api/feedback"
} finally {
  Remove-Item $envFile.FullName -Force -ErrorAction SilentlyContinue
}
