param(
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [int]$MaxWebhookCount = 10,
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

function Write-Result {
  param([Parameter(Mandatory = $true)][hashtable]$Payload)

  if ($Json) {
    $Payload | ConvertTo-Json -Depth 12
    return
  }

  Write-Host ("Bundle ID: " + $Payload.bundleId)
  if ($Payload.appId) {
    Write-Host ("App ID: " + $Payload.appId)
  }
  Write-Host ("Status: " + $(if ($Payload.ok) { "OK" } else { "NOT READY" }))
  if ($Payload.error) {
    Write-Host ("Error: " + $Payload.error)
  }
  if ($Payload.errorDetail) {
    Write-Host ("Error detail: " + $Payload.errorDetail)
  }
  if ($Payload.warning) {
    Write-Host ("Warning: " + $Payload.warning)
  }
  if ($Payload.webhookCount -ne $null) {
    Write-Host ("Webhooks: " + $Payload.webhookCount)
  }
  if ($Payload.deliveryReadOkCount -ne $null -and $Payload.webhookCount -ne $null) {
    Write-Host ("Deliveries readable: " + $Payload.deliveryReadOkCount + "/" + $Payload.webhookCount)
  }

  if ($Payload.webhooks -and @($Payload.webhooks).Count -gt 0) {
    Write-Host ""
    Write-Host "Webhook summary:"
    foreach ($webhook in @($Payload.webhooks)) {
      Write-Host ("- {0} | state={1} | deliveries={2}" -f $webhook.id, $webhook.state, $webhook.deliveriesStatus)
      if ($webhook.deliveryUrl) {
        Write-Host ("  URL: " + $webhook.deliveryUrl)
      }
      if ($webhook.lastDeliveryCreatedDate) {
        Write-Host ("  Last delivery: " + $webhook.lastDeliveryCreatedDate)
      }
      if ($webhook.errorDetail) {
        Write-Host ("  Detail: " + $webhook.errorDetail)
      }
    }
  }
}

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  throw "python is not available in PATH."
}
if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) {
  throw "ASC API key file not found."
}
if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
  throw "ASC key ID or issuer ID is missing."
}

$tempInputPath = Join-Path $env:TEMP ("ListenSDR-TestFlightWebhookHealth-" + [guid]::NewGuid().ToString("N") + ".json")
$requestPayload = [ordered]@{
  bundleId = $BundleId
  ascApiKeyPath = $AscApiKeyPath
  ascKeyId = $AscKeyId
  ascIssuerId = $AscIssuerId
  maxWebhookCount = $MaxWebhookCount
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

result = {
    "ok": False,
    "bundleId": bundle_id,
    "appId": None,
    "webhookCount": 0,
    "deliveryReadOkCount": 0,
    "webhooks": [],
    "error": None,
    "errorDetail": None,
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
if webhooks_status != 200:
    result["error"] = f"Unable to list webhooks ({webhooks_status})."
    result["errorDetail"] = first_error_detail(webhooks_payload)
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)

webhooks = webhooks_payload.get("data", [])
result["webhookCount"] = len(webhooks)

for webhook in webhooks:
    webhook_id = webhook.get("id")
    attrs = webhook.get("attributes", {}) if isinstance(webhook, dict) else {}
    item = {
        "id": webhook_id,
        "state": attrs.get("state"),
        "deliveryUrl": attrs.get("deliveryUrl"),
        "deliveriesStatus": None,
        "errorDetail": None,
        "lastDeliveryCreatedDate": None,
    }

    deliveries_url = f"https://api.appstoreconnect.apple.com/v1/webhooks/{webhook_id}/deliveries?limit=1&sort=-createdDate"
    deliveries_status, deliveries_payload = api_get(deliveries_url)
    item["deliveriesStatus"] = deliveries_status
    if deliveries_status == 200:
      result["deliveryReadOkCount"] += 1
      deliveries = deliveries_payload.get("data", [])
      if deliveries:
          first_delivery = deliveries[0]
          item["lastDeliveryCreatedDate"] = (first_delivery.get("attributes", {}) or {}).get("createdDate")
    else:
      item["errorDetail"] = first_error_detail(deliveries_payload)

    result["webhooks"].append(item)

if result["webhookCount"] == 0:
    result["warning"] = "No webhooks are configured for this app."
    result["ok"] = False
else:
    # Ready only when listing webhooks and deliveries works for all discovered webhooks.
    result["ok"] = (result["deliveryReadOkCount"] == result["webhookCount"])
    if not result["ok"]:
        result["warning"] = "At least one webhook exists, but deliveries are not readable for all webhooks."

print(json.dumps(result, ensure_ascii=False))
"@

  $raw = $pythonScript | python -
  if ($LASTEXITCODE -ne 0) {
    throw "Webhook health check failed."
  }
  $payload = ConvertFrom-JsonCompat -JsonText $raw
  if ($null -eq $payload.webhooks) {
    $payload.webhooks = @()
  } elseif (($payload.webhooks -is [System.Collections.IDictionary]) -and $payload.webhooks.Count -eq 0) {
    $payload.webhooks = @()
  } elseif (($payload.webhooks -is [System.Collections.IEnumerable]) -and -not ($payload.webhooks -is [string])) {
    $payload.webhooks = @($payload.webhooks)
  } else {
    $payload.webhooks = @($payload.webhooks)
  }
  Write-Result -Payload $payload
} finally {
  Remove-Item -Path $tempInputPath -ErrorAction SilentlyContinue
}
