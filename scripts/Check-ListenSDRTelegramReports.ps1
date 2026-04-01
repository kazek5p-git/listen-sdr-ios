param(
  [string]$ChatName = "listen sdr report system",
  [string]$OutputRoot = "C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\Telegram"
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

function ConvertFrom-MixedJsonOutput {
  param([Parameter(Mandatory = $true)][string]$RawText)

  $trimmed = $RawText.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    throw "No output to parse."
  }

  try {
    return ConvertFrom-JsonCompat -JsonText $trimmed
  } catch {
    $firstBrace = $trimmed.IndexOf("{")
    $lastBrace = $trimmed.LastIndexOf("}")
    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
      $candidate = $trimmed.Substring($firstBrace, $lastBrace - $firstBrace + 1)
      return ConvertFrom-JsonCompat -JsonText $candidate
    }

    throw ("Unable to locate JSON object in output: " + $trimmed)
  }
}

function Get-ReportPreview {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  $lines = Get-Content -Path $Path -Encoding UTF8
  $preview = [ordered]@{
    Path = $Path
    Type = $null
    Sender = $null
    Source = $null
    Time = $null
    Body = $null
  }

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    if ($line -like "Typ:*" -and -not $preview.Type) {
      $preview.Type = $line.Substring(4).Trim()
      continue
    }
    if ($line -like "Nadawca:*" -and -not $preview.Sender) {
      $preview.Sender = $line.Substring(8).Trim()
      continue
    }
    if ($line -like "Źródło:*" -and -not $preview.Source) {
      $preview.Source = $line.Substring(7).Trim()
      continue
    }
    if ($line -like "Czas:*" -and -not $preview.Time) {
      $preview.Time = $line.Substring(5).Trim()
      continue
    }
  }

  $bodyStart = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like "Treść sugestii:*" -or $lines[$i] -like "Treść zgłoszenia:*") {
      $bodyStart = $i + 1
      break
    }
  }

  if ($bodyStart -ge 0) {
    for ($i = $bodyStart; $i -lt $lines.Count; $i++) {
      $candidate = $lines[$i].Trim()
      if ([string]::IsNullOrWhiteSpace($candidate)) {
        continue
      }
      if ($candidate -like "Nadawca:*" -or $candidate -like "Źródło:*" -or $candidate -like "Czas:*") {
        break
      }
      $preview.Body = $candidate
      break
    }
  }

  return [pscustomobject]$preview
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$botScript = Join-Path $scriptRoot "Get-ListenSDRTelegramReports.ps1"
$tweeseCakeScript = Join-Path $scriptRoot "Read-ListenSDR-TweeseCakeTelegramChat.py"
$summaryPath = Join-Path $OutputRoot "latest-run.json"

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$summary = [ordered]@{
  ok = $true
  ranAt = (Get-Date).ToString("o")
  chatName = $ChatName
  outputRoot = $OutputRoot
  bot = $null
  tweeseCake = $null
}

try {
  $botRaw = & $botScript -Json -OutputRoot $OutputRoot 2>&1 | Out-String
  $botRaw = $botRaw.Trim()
  if (-not [string]::IsNullOrWhiteSpace($botRaw)) {
    $summary.bot = ConvertFrom-MixedJsonOutput -RawText $botRaw
  } else {
    $summary.bot = [ordered]@{
      ok = $false
      error = "Bot script returned no output."
    }
  }
} catch {
  $summary.bot = [ordered]@{
    ok = $false
    error = $_.Exception.Message
  }
}

try {
  $previousEncoding = $env:PYTHONIOENCODING
  $env:PYTHONIOENCODING = "utf-8"
  $tweeseCakeRaw = & python $tweeseCakeScript $ChatName $OutputRoot 2>&1 | Out-String
  if ($null -eq $previousEncoding) {
    Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue
  } else {
    $env:PYTHONIOENCODING = $previousEncoding
  }

  $tweeseCakeRaw = $tweeseCakeRaw.Trim()
  if (-not [string]::IsNullOrWhiteSpace($tweeseCakeRaw)) {
    $summary.tweeseCake = ConvertFrom-MixedJsonOutput -RawText $tweeseCakeRaw
  } else {
    $summary.tweeseCake = [ordered]@{
      ok = $false
      error = "TweeseCake script returned no output."
    }
  }
} catch {
  $summary.tweeseCake = [ordered]@{
    ok = $false
    error = $_.Exception.Message
  }
}

if (($summary.bot -and $summary.bot.ok -eq $false) -and ($summary.tweeseCake -and $summary.tweeseCake.ok -eq $false)) {
  $summary.ok = $false
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 10), $utf8NoBom)

Write-Host ("Raporty: {0}" -f $OutputRoot)
if ($summary.bot) {
  Write-Host ("Bot API: ok={0}" -f $summary.bot.ok)
  if ($summary.bot.matchedMessages -ne $null) {
    Write-Host ("Bot API dopasowane: {0}" -f $summary.bot.matchedMessages)
  }
  if ($summary.bot.error) {
    Write-Host ("Bot API błąd: {0}" -f $summary.bot.error)
  }
}
if ($summary.tweeseCake) {
  Write-Host ("TweeseCake: ok={0}" -f $summary.tweeseCake.ok)
  if ($summary.tweeseCake.items) {
    Write-Host ("TweeseCake wpisy: {0}" -f @($summary.tweeseCake.items).Count)
  }
  if ($summary.tweeseCake.downloadedFiles) {
    Write-Host ("TweeseCake załączniki: {0}" -f @($summary.tweeseCake.downloadedFiles).Count)
  }
  if ($summary.tweeseCake.error) {
    Write-Host ("TweeseCake błąd: {0}" -f $summary.tweeseCake.error)
  }
}
Write-Host ("Podsumowanie JSON: {0}" -f $summaryPath)

$newFiles = @()
if ($summary.tweeseCake -and $summary.tweeseCake.downloadedFiles) {
  $newFiles = @($summary.tweeseCake.downloadedFiles)
}

if ($newFiles.Count -gt 0) {
  Write-Host ""
  Write-Host "Nowe lub zaktualizowane załączniki:"
  foreach ($file in $newFiles) {
    $preview = Get-ReportPreview -Path $file
    if ($null -eq $preview) {
      Write-Host ("- {0}" -f $file)
      continue
    }

    Write-Host ("- {0}" -f $preview.Path)
    if ($preview.Type -or $preview.Sender) {
      Write-Host ("  {0} | {1}" -f $preview.Type, $preview.Sender)
    }
    if ($preview.Source -or $preview.Time) {
      Write-Host ("  {0} | {1}" -f $preview.Source, $preview.Time)
    }
    if ($preview.Body) {
      Write-Host ("  {0}" -f $preview.Body)
    }
  }
}
