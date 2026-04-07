param(
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$OutputRoot = "C:\Users\Kazek\Desktop\iOS\ListenSDR\Reports\TestFlight",
  [int]$MaxWebhookCount = 10,
  [int]$MaxDeliveriesPerWebhook = 50,
  [string[]]$EventKeywords = @("feedback", "crash"),
  [switch]$IncludeAlreadySeen,
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

function Write-JsonErrorAndExit {
  param([Parameter(Mandatory = $true)][string]$Message)

  if ($Json) {
    [ordered]@{
      ok = $false
      error = $Message
      outputRoot = $OutputRoot
    } | ConvertTo-Json -Depth 8
    exit 0
  }

  throw $Message
}

function Get-StateDirectory {
  Join-Path $env:APPDATA "ListenSDR\testflight-reports"
}

function Get-StatePath {
  Join-Path (Get-StateDirectory) "state.json"
}

function Read-State {
  $statePath = Get-StatePath
  if (-not (Test-Path $statePath)) {
    return [ordered]@{
      seenDeliveryIds = @()
      lastRunAt = $null
    }
  }

  $raw = Get-Content -Path $statePath -Raw
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [ordered]@{
      seenDeliveryIds = @()
      lastRunAt = $null
    }
  }

  $state = ConvertFrom-JsonCompat -JsonText $raw
  if (-not $state.seenDeliveryIds) {
    $state.seenDeliveryIds = @()
  } else {
    $state.seenDeliveryIds = @($state.seenDeliveryIds)
  }
  return $state
}

function Write-State {
  param([Parameter(Mandatory = $true)][hashtable]$State)

  $stateDir = Get-StateDirectory
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  $State.lastRunAt = (Get-Date).ToString("o")
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText((Get-StatePath), ($State | ConvertTo-Json -Depth 10), $utf8NoBom)
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

function Test-MatchesEventKeywords {
  param(
    [Parameter(Mandatory = $true)]$Delivery,
    [Parameter(Mandatory = $true)][string[]]$Keywords
  )

  if (-not $Keywords -or $Keywords.Count -eq 0) {
    return $true
  }

  $searchParts = @(
    [string]$Delivery.eventType,
    [string]$Delivery.notificationType,
    [string]$Delivery.subType,
    [string]$Delivery.summary,
    [string]$Delivery.rawType
  )
  $haystack = ($searchParts -join " ").ToLowerInvariant()
  foreach ($keyword in $Keywords) {
    if ([string]::IsNullOrWhiteSpace($keyword)) {
      continue
    }
    if ($haystack.Contains($keyword.ToLowerInvariant())) {
      return $true
    }
  }
  return $false
}

function Assert-Prerequisites {
  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python is not available in PATH."
  }
  if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) {
    throw "ASC API key file not found."
  }
  if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
    throw "ASC key ID or issuer ID is missing."
  }
}

function Invoke-AscWebhookCheck {
  $tempInputPath = Join-Path $env:TEMP ("ListenSDR-TestFlightCheck-" + [guid]::NewGuid().ToString("N") + ".json")
  $requestPayload = [ordered]@{
    bundleId = $BundleId
    ascApiKeyPath = $AscApiKeyPath
    ascKeyId = $AscKeyId
    ascIssuerId = $AscIssuerId
    maxWebhookCount = $MaxWebhookCount
    maxDeliveriesPerWebhook = $MaxDeliveriesPerWebhook
  }

  $requestPayload | ConvertTo-Json -Depth 8 | Set-Content -Path $tempInputPath -Encoding utf8

  try {
    $pythonScript = @"
import base64
import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils

payload = json.loads(Path(r'''$tempInputPath''').read_text(encoding='utf-8-sig'))
bundle_id = payload["bundleId"]
key_path = Path(payload["ascApiKeyPath"])
key_id = payload["ascKeyId"]
issuer_id = payload["ascIssuerId"]
max_webhooks = int(payload["maxWebhookCount"])
max_deliveries = int(payload["maxDeliveriesPerWebhook"])

private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def make_jwt() -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    token_payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing_input = (
        f"{b64url(json.dumps(header, separators=(',', ':')).encode())}."
        f"{b64url(json.dumps(token_payload, separators=(',', ':')).encode())}"
    )
    signature_der = private_key.sign(signing_input.encode("ascii"), ec.ECDSA(hashes.SHA256()))
    r_value, s_value = utils.decode_dss_signature(signature_der)
    signature_raw = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
    return f"{signing_input}.{b64url(signature_raw)}"

token = make_jwt()
headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

def api_get(url: str):
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw}
        return exc.code, parsed

def first_error_detail(body):
    if not isinstance(body, dict):
        return ""
    errors = body.get("errors")
    if not errors:
        return ""
    first = errors[0] if isinstance(errors, list) and errors else {}
    if not isinstance(first, dict):
        return ""
    return str(first.get("detail") or first.get("title") or "")

def best_event_fields(attributes: dict):
    if not isinstance(attributes, dict):
        return ("", "", "", "")
    event_type = str(
        attributes.get("eventType")
        or attributes.get("notificationType")
        or attributes.get("type")
        or ""
    )
    notification_type = str(attributes.get("notificationType") or "")
    sub_type = str(attributes.get("subType") or attributes.get("eventSubType") or "")
    summary = str(
        attributes.get("summary")
        or attributes.get("message")
        or attributes.get("result")
        or attributes.get("state")
        or ""
    )
    return (event_type, notification_type, sub_type, summary)

result = {
    "ok": False,
    "bundleId": bundle_id,
    "appId": None,
    "webhooks": [],
    "deliveries": [],
    "error": None,
    "warning": None,
}

apps_url = "https://api.appstoreconnect.apple.com/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id, "limit": "1"})
apps_status, apps_payload = api_get(apps_url)
if apps_status != 200:
    result["error"] = f"Unable to read app by bundleId ({apps_status})."
    result["errorDetail"] = first_error_detail(apps_payload)
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

apps = apps_payload.get("data", [])
if not apps:
    result["error"] = "Bundle ID was not found in App Store Connect."
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

app_id = apps[0].get("id")
result["appId"] = app_id

webhooks_url = "https://api.appstoreconnect.apple.com/v1/webhooks?" + urllib.parse.urlencode({"filter[app]": app_id, "limit": str(max_webhooks)})
webhooks_status, webhooks_payload = api_get(webhooks_url)
if webhooks_status == 403:
    result["error"] = "Webhook access is forbidden for current ASC credentials."
    result["errorDetail"] = first_error_detail(webhooks_payload)
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)
if webhooks_status != 200:
    result["error"] = f"Unable to list webhooks ({webhooks_status})."
    result["errorDetail"] = first_error_detail(webhooks_payload)
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

webhooks = webhooks_payload.get("data", [])
for webhook in webhooks:
    webhook_id = webhook.get("id")
    webhook_attrs = webhook.get("attributes", {}) if isinstance(webhook, dict) else {}
    result["webhooks"].append({
        "id": webhook_id,
        "state": webhook_attrs.get("state"),
        "deliveryUrl": webhook_attrs.get("deliveryUrl"),
    })

    deliveries_url = f"https://api.appstoreconnect.apple.com/v1/webhooks/{webhook_id}/deliveries?" + urllib.parse.urlencode({"limit": str(max_deliveries), "sort": "-createdDate"})
    deliveries_status, deliveries_payload = api_get(deliveries_url)
    if deliveries_status != 200:
        result["warning"] = f"Failed to read deliveries for webhook {webhook_id} ({deliveries_status})."
        continue

    deliveries = deliveries_payload.get("data", [])
    included = deliveries_payload.get("included", [])
    included_by_key = {}
    for item in included:
        if not isinstance(item, dict):
            continue
        key = (item.get("type"), item.get("id"))
        included_by_key[key] = item

    for delivery in deliveries:
        delivery_id = delivery.get("id")
        attributes = delivery.get("attributes", {}) if isinstance(delivery, dict) else {}
        event_type, notification_type, sub_type, summary = best_event_fields(attributes)
        raw_type = str(delivery.get("type") or "")
        relationships = delivery.get("relationships", {}) if isinstance(delivery, dict) else {}

        related_items = []
        if isinstance(relationships, dict):
            for rel_name, rel_value in relationships.items():
                rel_data = None
                if isinstance(rel_value, dict):
                    rel_data = rel_value.get("data")
                if isinstance(rel_data, dict):
                    rel_type = rel_data.get("type")
                    rel_id = rel_data.get("id")
                    included_item = included_by_key.get((rel_type, rel_id))
                    related_items.append({
                        "name": rel_name,
                        "type": rel_type,
                        "id": rel_id,
                        "attributes": (included_item or {}).get("attributes", {}),
                    })
                elif isinstance(rel_data, list):
                    for rel_entry in rel_data:
                        if not isinstance(rel_entry, dict):
                            continue
                        rel_type = rel_entry.get("type")
                        rel_id = rel_entry.get("id")
                        included_item = included_by_key.get((rel_type, rel_id))
                        related_items.append({
                            "name": rel_name,
                            "type": rel_type,
                            "id": rel_id,
                            "attributes": (included_item or {}).get("attributes", {}),
                        })

        result["deliveries"].append({
            "deliveryId": delivery_id,
            "webhookId": webhook_id,
            "createdDate": attributes.get("createdDate"),
            "status": attributes.get("status") or attributes.get("state") or attributes.get("result"),
            "eventType": event_type,
            "notificationType": notification_type,
            "subType": sub_type,
            "summary": summary,
            "rawType": raw_type,
            "attributes": attributes,
            "related": related_items,
        })

result["ok"] = True
print(json.dumps(result, ensure_ascii=False))
"@

    $raw = $pythonScript | python -
    if ($LASTEXITCODE -ne 0) {
      throw "ASC webhook check failed."
    }
    return (ConvertFrom-JsonCompat -JsonText $raw)
  } finally {
    Remove-Item -Path $tempInputPath -ErrorAction SilentlyContinue
  }
}

Assert-Prerequisites
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$state = Read-State
$seenIds = @($state.seenDeliveryIds)
$seenLookup = @{}
foreach ($id in $seenIds) {
  if (-not [string]::IsNullOrWhiteSpace([string]$id)) {
    $seenLookup[[string]$id] = $true
  }
}

$result = Invoke-AscWebhookCheck

$summary = [ordered]@{
  ok = [bool]$result.ok
  ranAt = (Get-Date).ToString("o")
  bundleId = $BundleId
  outputRoot = $OutputRoot
  appId = $result.appId
  webhookCount = @($result.webhooks).Count
  deliveryCount = @($result.deliveries).Count
  error = $result.error
  errorDetail = $result.errorDetail
  warning = $result.warning
  matchedDeliveries = @()
  savedFiles = @()
}

if ($result.ok -and $result.deliveries) {
  $deliveries = @($result.deliveries) | Sort-Object -Property createdDate -Descending
  foreach ($delivery in $deliveries) {
    $deliveryId = [string]$delivery.deliveryId
    if ([string]::IsNullOrWhiteSpace($deliveryId)) {
      continue
    }

    if (-not (Test-MatchesEventKeywords -Delivery $delivery -Keywords $EventKeywords)) {
      continue
    }

    $summary.matchedDeliveries += $delivery
    if (-not $IncludeAlreadySeen -and $seenLookup.ContainsKey($deliveryId)) {
      continue
    }

    $createdDate = [string]$delivery.createdDate
    $datePart = (Get-Date).ToString("yyyy-MM-dd")
    if (-not [string]::IsNullOrWhiteSpace($createdDate)) {
      try {
        $parsedCreated = [DateTimeOffset]::Parse($createdDate)
        $datePart = $parsedCreated.ToString("yyyy-MM-dd")
      } catch {
        $null = $null
      }
    }

    $folder = Join-Path $OutputRoot $datePart
    New-Item -ItemType Directory -Path $folder -Force | Out-Null

    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    if (-not [string]::IsNullOrWhiteSpace($createdDate)) {
      try {
        $stamp = ([DateTimeOffset]::Parse($createdDate)).ToString("yyyyMMdd-HHmmss")
      } catch {
        $null = $null
      }
    }
    $fileNameBase = Convert-ToSafeFileName -Value ("testflight-delivery-" + $stamp + "-" + $deliveryId)
    $jsonPath = Join-Path $folder ($fileNameBase + ".json")
    $txtPath = Join-Path $folder ($fileNameBase + ".txt")

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($jsonPath, ($delivery | ConvertTo-Json -Depth 20), $utf8NoBom)

    $lines = @(
      "Źródło: TestFlight / App Store Connect webhook",
      "Delivery ID: $deliveryId",
      "Webhook ID: $($delivery.webhookId)",
      "Czas: $($delivery.createdDate)",
      "Typ zdarzenia: $($delivery.eventType)",
      "Notification type: $($delivery.notificationType)",
      "Sub type: $($delivery.subType)",
      "Status: $($delivery.status)",
      "Podsumowanie: $($delivery.summary)",
      ""
    )
    if ($delivery.related) {
      $lines += "Powiązane obiekty:"
      foreach ($related in @($delivery.related)) {
        $lines += ("- {0}: {1} ({2})" -f $related.name, $related.id, $related.type)
      }
      $lines += ""
    }
    $lines += "Pełny payload: $jsonPath"
    [System.IO.File]::WriteAllText($txtPath, ($lines -join [Environment]::NewLine), $utf8NoBom)

    $summary.savedFiles += $txtPath
    $seenLookup[$deliveryId] = $true
  }
}

$state.seenDeliveryIds = @($seenLookup.Keys | Sort-Object | Select-Object -Last 5000)
Write-State -State $state

$latestRunPath = Join-Path $OutputRoot "latest-run.json"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($latestRunPath, ($summary | ConvertTo-Json -Depth 20), $utf8NoBom)

if ($Json) {
  $summary | ConvertTo-Json -Depth 20
  exit 0
}

Write-Host ("Output: " + $OutputRoot)
Write-Host ("App ID: " + $summary.appId)
Write-Host ("Webhooks: " + $summary.webhookCount)
Write-Host ("Deliveries (raw): " + $summary.deliveryCount)
Write-Host ("Deliveries (matched): " + @($summary.matchedDeliveries).Count)
Write-Host ("Saved new files: " + @($summary.savedFiles).Count)

if ($summary.error) {
  Write-Host ("Error: " + $summary.error)
}
if ($summary.errorDetail) {
  Write-Host ("Error detail: " + $summary.errorDetail)
}
if ($summary.warning) {
  Write-Host ("Warning: " + $summary.warning)
}

if (@($summary.savedFiles).Count -gt 0) {
  Write-Host ""
  Write-Host "New TestFlight reports:"
  foreach ($file in @($summary.savedFiles)) {
    Write-Host ("- " + $file)
  }
}

Write-Host ("Latest run: " + $latestRunPath)
