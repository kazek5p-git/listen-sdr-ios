param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("bot-token", "chat-id")]
  [string]$SecretName,

  [string]$SecretValue
)

$ErrorActionPreference = "Stop"

function Get-SecretFilePath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $baseDir = Join-Path $env:APPDATA "ListenSDR\secrets"
  return Join-Path $baseDir ("telegram-reports-" + $Name + ".txt")
}

if ([string]::IsNullOrWhiteSpace($SecretValue)) {
  $securePrompt = Read-Host -AsSecureString "Podaj wartość sekretu $SecretName"
} else {
  $securePrompt = ConvertTo-SecureString -String $SecretValue -AsPlainText -Force
}

$secretPath = Get-SecretFilePath -Name $SecretName
$secretDir = Split-Path -Parent $secretPath
New-Item -ItemType Directory -Path $secretDir -Force | Out-Null

$encrypted = ConvertFrom-SecureString -SecureString $securePrompt
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($secretPath, $encrypted, $utf8NoBom)

Write-Host "Sekret $SecretName zapisany w $secretPath"
