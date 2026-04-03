param(
  [string]$BotToken = [Environment]::GetEnvironmentVariable("LISTEN_SDR_BOT_TOKEN", "User"),
  [string]$ChatId = [Environment]::GetEnvironmentVariable("LISTEN_SDR_TELEGRAM_REPORTS_CHAT_ID", "User"),
  [string]$ChatTitle = "listen sdr report system",
  [string]$OutputRoot = "C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\Telegram",
  [int]$MaxUpdates = 50,
  [switch]$IncludeAlreadySeen,
  [switch]$SkipFileDownloads,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function ConvertTo-HashtableCompat {
  param($InputObject)

  if ($null -eq $InputObject) {
    return $null
  }

  if ($InputObject -is [System.Collections.IDictionary]) {
    $result = [ordered]@{}
    foreach ($key in $InputObject.Keys) {
      $result[$key] = ConvertTo-HashtableCompat -InputObject $InputObject[$key]
    }
    return $result
  }

  if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
    $items = @()
    foreach ($item in $InputObject) {
      $items += ,(ConvertTo-HashtableCompat -InputObject $item)
    }
    return $items
  }

  if ($InputObject -is [psobject] -and $InputObject.PSObject.Properties.Count -gt 0) {
    $result = [ordered]@{}
    foreach ($property in $InputObject.PSObject.Properties) {
      $result[$property.Name] = ConvertTo-HashtableCompat -InputObject $property.Value
    }
    return $result
  }

  return $InputObject
}

function ConvertFrom-JsonCompat {
  param([Parameter(Mandatory = $true)][string]$JsonText)

  $parsed = $JsonText | ConvertFrom-Json
  return ConvertTo-HashtableCompat -InputObject $parsed
}

function Get-SecretFilePath {
  param([Parameter(Mandatory = $true)][string]$Name)

  $baseDir = Join-Path $env:APPDATA "ListenSDR\secrets"
  return Join-Path $baseDir ("telegram-reports-" + $Name + ".txt")
}

function Write-JsonErrorAndExit {
  param([Parameter(Mandatory = $true)][string]$Message)

  if ($Json) {
    $payload = [ordered]@{
      ok = $false
      error = $Message
      outputRoot = $OutputRoot
    }
    $payload | ConvertTo-Json -Depth 5
    exit 0
  }

  throw $Message
}

function Read-SecretValue {
  param([Parameter(Mandatory = $true)][string]$Name)

  $secretPath = Get-SecretFilePath -Name $Name
  if (-not (Test-Path $secretPath)) {
    return $null
  }

  $encrypted = Get-Content -Path $secretPath -Raw
  if ([string]::IsNullOrWhiteSpace($encrypted)) {
    return $null
  }

  $trimmed = $encrypted.Trim()

  try {
    $secureValue = ConvertTo-SecureString -String $trimmed
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
      return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
      if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
      }
    }
  } catch {
    if ($trimmed -notmatch '^[0-9a-fA-F]+$') {
      return $trimmed
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $python) {
      throw
    }

    $pythonScript = @"
from pathlib import Path
import binascii
import sys
import win32crypt

raw = Path(sys.argv[1]).read_text(encoding='utf-8').strip()
data = binascii.unhexlify(raw)
plain = win32crypt.CryptUnprotectData(data, None, None, None, 0)[1]
sys.stdout.write(plain.decode('utf-16-le'))
"@

    $decoded = & python -c $pythonScript $secretPath 2>$null
    if ($LASTEXITCODE -ne 0) {
      throw
    }

    return ($decoded | Out-String).Trim()
  }
}

function Get-ChatIdSecretValue {
  $chatIdSecretPath = Get-SecretFilePath -Name "chat-id"
  if (-not (Test-Path $chatIdSecretPath)) {
    return $null
  }

  try {
    return Read-SecretValue -Name "chat-id"
  } catch {
    return $null
  }
}

function Get-BotTokenSecretValue {
  $botTokenSecretPath = Get-SecretFilePath -Name "bot-token"
  if (-not (Test-Path $botTokenSecretPath)) {
    return $null
  }

  try {
    return Read-SecretValue -Name "bot-token"
  } catch {
    return $null
  }
}

function Ensure-BotCredentials {
  if ([string]::IsNullOrWhiteSpace($ChatId)) {
    $script:ChatId = Get-ChatIdSecretValue
  }

  if ([string]::IsNullOrWhiteSpace($BotToken)) {
    $script:BotToken = Get-BotTokenSecretValue
  }

  if ([string]::IsNullOrWhiteSpace($BotToken)) {
    Write-JsonErrorAndExit -Message "Brak tokenu bota Telegram. Ustaw LISTEN_SDR_BOT_TOKEN albo zapisz go skryptem Set-ListenSDRTelegramReportsSecret.ps1 -SecretName bot-token."
  }

  if ([string]::IsNullOrWhiteSpace($ChatId) -and [string]::IsNullOrWhiteSpace($ChatTitle)) {
    Write-JsonErrorAndExit -Message "Brak chat-id raportów Telegram i brak ChatTitle. Ustaw LISTEN_SDR_TELEGRAM_REPORTS_CHAT_ID albo zapisz go skryptem Set-ListenSDRTelegramReportsSecret.ps1 -SecretName chat-id."
  }
}

function Write-SecretValue {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $secretPath = Get-SecretFilePath -Name $Name
  $secretDir = Split-Path -Parent $secretPath
  New-Item -ItemType Directory -Path $secretDir -Force | Out-Null

  $secureValue = ConvertTo-SecureString -String $Value -AsPlainText -Force
  $encrypted = ConvertFrom-SecureString -SecureString $secureValue
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($secretPath, $encrypted, $utf8NoBom)
}

function Get-StateDirectory {
  return Join-Path $env:APPDATA "ListenSDR\telegram-reports"
}

function Get-StatePath {
  return Join-Path (Get-StateDirectory) "state.json"
}

function Read-State {
  $statePath = Get-StatePath
  if (-not (Test-Path $statePath)) {
    return [ordered]@{
      lastUpdateId = 0
      lastRunAt = $null
    }
  }

  $raw = Get-Content -Path $statePath -Raw
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [ordered]@{
      lastUpdateId = 0
      lastRunAt = $null
    }
  }

  return ConvertFrom-JsonCompat -JsonText $raw
}

function Write-State {
  param([Parameter(Mandatory = $true)][hashtable]$State)

  $stateDir = Get-StateDirectory
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

  $state.lastRunAt = (Get-Date).ToString("o")
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText((Get-StatePath), ($State | ConvertTo-Json -Depth 8), $utf8NoBom)
}

function Invoke-TelegramGet {
  param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$Method,
    [hashtable]$Query = @{}
  )

  $queryPairs = @()
  foreach ($entry in $Query.GetEnumerator()) {
    if ($null -eq $entry.Value -or $entry.Value -eq "") {
      continue
    }

    $queryPairs += ([uri]::EscapeDataString([string]$entry.Key) + "=" + [uri]::EscapeDataString([string]$entry.Value))
  }

  $uri = "https://api.telegram.org/bot$Token/$Method"
  if ($queryPairs.Count -gt 0) {
    $uri += "?" + ($queryPairs -join "&")
  }

  $response = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 30
  if (-not $response.ok) {
    throw "Telegram API returned an error for $Method."
  }

  return $response.result
}

function Invoke-TelegramBinaryDownload {
  param(
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $downloadUri = "https://api.telegram.org/file/bot$Token/$FilePath"
  Invoke-WebRequest -Uri $downloadUri -OutFile $DestinationPath -TimeoutSec 60 | Out-Null
}

function Get-MessagePayload {
  param([Parameter(Mandatory = $true)]$Update)

  foreach ($propertyName in @("message", "edited_message", "channel_post", "edited_channel_post")) {
    if ($null -ne $Update.$propertyName) {
      return $Update.$propertyName
    }
  }

  return $null
}

function Get-ChatDisplayName {
  param([Parameter(Mandatory = $true)]$Chat)

  if (-not [string]::IsNullOrWhiteSpace($Chat.title)) {
    return $Chat.title
  }
  if (-not [string]::IsNullOrWhiteSpace($Chat.username)) {
    return $Chat.username
  }

  $name = @($Chat.first_name, $Chat.last_name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " "
  return $name.Trim()
}

function Convert-ToSafeFileName {
  param([Parameter(Mandatory = $true)][string]$Value)

  $safe = $Value -replace '[<>:"/\\|?*\x00-\x1F]', "-"
  $safe = $safe.Trim()
  if ([string]::IsNullOrWhiteSpace($safe)) {
    return "unknown"
  }

  return $safe
}

function Get-MessageText {
  param([Parameter(Mandatory = $true)]$Message)

  if (-not [string]::IsNullOrWhiteSpace($Message.text)) {
    return $Message.text
  }
  if (-not [string]::IsNullOrWhiteSpace($Message.caption)) {
    return $Message.caption
  }
  return ""
}

function Get-FromDisplay {
  param([Parameter(Mandatory = $true)]$Message)

  if ($null -eq $Message.from) {
    return "unknown"
  }

  if (-not [string]::IsNullOrWhiteSpace($Message.from.username)) {
    return $Message.from.username
  }

  $name = @($Message.from.first_name, $Message.from.last_name | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " "
  if (-not [string]::IsNullOrWhiteSpace($name)) {
    return $name.Trim()
  }

  return [string]$Message.from.id
}

function Get-AttachmentDescriptor {
  param([Parameter(Mandatory = $true)]$Message)

  if ($null -ne $Message.document) {
    return [ordered]@{
      kind = "document"
      fileId = $Message.document.file_id
      fileName = if ($Message.document.file_name) { $Message.document.file_name } else { "document" }
      mimeType = $Message.document.mime_type
    }
  }

  if ($null -ne $Message.audio) {
    return [ordered]@{
      kind = "audio"
      fileId = $Message.audio.file_id
      fileName = if ($Message.audio.file_name) { $Message.audio.file_name } else { "audio.mp3" }
      mimeType = $Message.audio.mime_type
    }
  }

  if ($null -ne $Message.voice) {
    return [ordered]@{
      kind = "voice"
      fileId = $Message.voice.file_id
      fileName = "voice.ogg"
      mimeType = $Message.voice.mime_type
    }
  }

  if ($null -ne $Message.video) {
    return [ordered]@{
      kind = "video"
      fileId = $Message.video.file_id
      fileName = if ($Message.video.file_name) { $Message.video.file_name } else { "video.mp4" }
      mimeType = $Message.video.mime_type
    }
  }

  if ($null -ne $Message.animation) {
    return [ordered]@{
      kind = "animation"
      fileId = $Message.animation.file_id
      fileName = if ($Message.animation.file_name) { $Message.animation.file_name } else { "animation.mp4" }
      mimeType = $Message.animation.mime_type
    }
  }

  if ($null -ne $Message.photo -and $Message.photo.Count -gt 0) {
    $largestPhoto = $Message.photo | Sort-Object file_size -Descending | Select-Object -First 1
    return [ordered]@{
      kind = "photo"
      fileId = $largestPhoto.file_id
      fileName = "photo.jpg"
      mimeType = "image/jpeg"
    }
  }

  return $null
}

Ensure-BotCredentials

$webhookInfo = Invoke-TelegramGet -Token $BotToken -Method "getWebhookInfo"
if (-not [string]::IsNullOrWhiteSpace($webhookInfo.url)) {
  throw "Bot ma aktywny webhook ($($webhookInfo.url)). Ten skrypt używa getUpdates, więc webhook trzeba wyłączyć albo użyć osobnego bota do grupy."
}

$state = Read-State
$offset = if ($IncludeAlreadySeen) { $null } else { [int64]$state.lastUpdateId + 1 }
$updates = Invoke-TelegramGet -Token $BotToken -Method "getUpdates" -Query @{
  timeout = 1
  limit = $MaxUpdates
  offset = $offset
}

if ($null -eq $updates) {
  $updates = @()
}

$matchedMessages = New-Object System.Collections.Generic.List[object]
$maxSeenUpdateId = [int64]$state.lastUpdateId

foreach ($update in $updates) {
  if ([int64]$update.update_id -gt $maxSeenUpdateId) {
    $maxSeenUpdateId = [int64]$update.update_id
  }

  $message = Get-MessagePayload -Update $update
  if ($null -eq $message -or $null -eq $message.chat) {
    continue
  }

  $chatName = Get-ChatDisplayName -Chat $message.chat
  $chatIdMatches = -not [string]::IsNullOrWhiteSpace($ChatId) -and ([string]$message.chat.id -eq [string]$ChatId)
  $chatTitleMatches = -not [string]::IsNullOrWhiteSpace($ChatTitle) -and ($chatName -ieq $ChatTitle)
  if (-not $chatIdMatches -and -not $chatTitleMatches) {
    continue
  }

  $messageText = Get-MessageText -Message $message
  $attachment = Get-AttachmentDescriptor -Message $message
  $messageDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$message.date).ToLocalTime()
  $safeChatName = Convert-ToSafeFileName -Value $chatName
  $dayDir = Join-Path $OutputRoot ($messageDate.ToString("yyyy-MM-dd"))
  $entryBaseName = "{0}-u{1}-m{2}" -f $messageDate.ToString("yyyyMMdd-HHmmss"), $update.update_id, $message.message_id

  New-Item -ItemType Directory -Path $dayDir -Force | Out-Null

  $entry = [ordered]@{
    updateId = [int64]$update.update_id
    messageId = [int64]$message.message_id
    chatId = [string]$message.chat.id
    chatName = $chatName
    from = Get-FromDisplay -Message $message
    sentAt = $messageDate.ToString("yyyy-MM-dd HH:mm:ss zzz")
    text = $messageText
    attachment = $null
    metadataPath = $null
  }

  if ($attachment -and -not $SkipFileDownloads) {
    $fileInfo = Invoke-TelegramGet -Token $BotToken -Method "getFile" -Query @{ file_id = $attachment.fileId }
    $extension = [System.IO.Path]::GetExtension($attachment.fileName)
    if ([string]::IsNullOrWhiteSpace($extension)) {
      $extension = [System.IO.Path]::GetExtension($fileInfo.file_path)
    }
    if ([string]::IsNullOrWhiteSpace($extension)) {
      $extension = ".bin"
    }

    $safeAttachmentName = Convert-ToSafeFileName -Value ([System.IO.Path]::GetFileNameWithoutExtension($attachment.fileName))
    $downloadPath = Join-Path $dayDir ($entryBaseName + "-" + $safeAttachmentName + $extension)
    Invoke-TelegramBinaryDownload -Token $BotToken -FilePath $fileInfo.file_path -DestinationPath $downloadPath
    $entry.attachment = [ordered]@{
      kind = $attachment.kind
      path = $downloadPath
      originalName = $attachment.fileName
      telegramPath = $fileInfo.file_path
      mimeType = $attachment.mimeType
    }
  } elseif ($attachment) {
    $entry.attachment = [ordered]@{
      kind = $attachment.kind
      originalName = $attachment.fileName
      mimeType = $attachment.mimeType
    }
  }

  $metadataPath = Join-Path $dayDir ($entryBaseName + "-" + $safeChatName + ".json")
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($metadataPath, ($entry | ConvertTo-Json -Depth 8), $utf8NoBom)
  $entry.metadataPath = $metadataPath
  $matchedMessages.Add([pscustomobject]$entry)
}

if ([string]::IsNullOrWhiteSpace($ChatId) -and $matchedMessages.Count -gt 0) {
  $resolvedChatId = [string]$matchedMessages[0].chatId
  if (-not [string]::IsNullOrWhiteSpace($resolvedChatId)) {
    Write-SecretValue -Name "chat-id" -Value $resolvedChatId
    $ChatId = $resolvedChatId
  }
}

if (-not $IncludeAlreadySeen) {
  $state.lastUpdateId = $maxSeenUpdateId
  Write-State -State $state
}

$chatFilterValue = $ChatTitle
if (-not [string]::IsNullOrWhiteSpace($ChatId)) {
  $chatFilterValue = $ChatId
}

$result = New-Object System.Collections.Hashtable
$null = $result.Add('ok', $true)
$null = $result.Add('chatFilter', [string]$chatFilterValue)
$null = $result.Add('fetchedUpdates', @($updates).Count)
$null = $result.Add('matchedMessages', $matchedMessages.Count)
$null = $result.Add('outputRoot', $OutputRoot)
$null = $result.Add('items', [object[]]@($matchedMessages.ToArray()))

if ($Json) {
  $result | ConvertTo-Json -Depth 8
  return
}

Write-Host "Pobrane aktualizacje: $($result.fetchedUpdates)"
Write-Host "Dopasowane zgłoszenia: $($result.matchedMessages)"
Write-Host "Folder: $OutputRoot"

if ($matchedMessages.Count -eq 0) {
  Write-Host "Brak nowych zgłoszeń."
  return
}

foreach ($item in $matchedMessages) {
  Write-Host ""
  Write-Host ("[{0}] {1}" -f $item.sentAt, $item.from)
  Write-Host ("Chat: {0} ({1})" -f $item.chatName, $item.chatId)

  if (-not [string]::IsNullOrWhiteSpace($item.text)) {
    Write-Host $item.text
  } else {
    Write-Host "[bez tekstu]"
  }

  if ($null -ne $item.attachment) {
    if ($item.attachment.path) {
      Write-Host ("Zalacznik: {0} -> {1}" -f $item.attachment.kind, $item.attachment.path)
    } else {
      Write-Host ("Zalacznik: {0} ({1})" -f $item.attachment.kind, $item.attachment.originalName)
    }
  }

  Write-Host ("Metadane: {0}" -f $item.metadataPath)
}
