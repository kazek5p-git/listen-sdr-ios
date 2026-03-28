param(
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$BuildVersion,
  [int]$MaxResults = 5,
  [switch]$WaitUntilProcessed,
  [int]$PollIntervalSeconds = 10,
  [int]$TimeoutMinutes = 20,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

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
  if ($MaxResults -lt 1) {
    throw "MaxResults must be greater than 0."
  }
  if ($PollIntervalSeconds -lt 5) {
    throw "PollIntervalSeconds must be at least 5."
  }
  if ($TimeoutMinutes -lt 1) {
    throw "TimeoutMinutes must be at least 1."
  }
}

function Get-TestFlightStatus {
  $pythonScript = @"
import base64, json, sys, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils

bundle_id = r'''$BundleId'''
key_path = Path(r'''$AscApiKeyPath''')
key_id = r'''$AscKeyId'''
issuer_id = r'''$AscIssuerId'''
build_version = r'''$BuildVersion'''
max_results = int(r'''$MaxResults''')

private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')

def build_jwt() -> str:
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    der_sig = private_key.sign(signing_input.encode('ascii'), ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_sig)
    raw_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    return f"{signing_input}.{b64url(raw_sig)}"

def api_get(url: str, token: str):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode('utf-8'))

token = build_jwt()

try:
    app_url = "https://api.appstoreconnect.apple.com/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id})
    app_payload = api_get(app_url, token)
    apps = app_payload.get("data", [])
    if not apps:
        print(json.dumps({"ok": False, "error": "APP_NOT_FOUND", "bundleId": bundle_id}))
        sys.exit(0)

    app = apps[0]
    app_id = app.get("id")
    build_query = {"filter[app]": app_id, "limit": str(max_results), "sort": "-uploadedDate"}
    if build_version:
        build_query["filter[version]"] = build_version
    build_url = "https://api.appstoreconnect.apple.com/v1/builds?" + urllib.parse.urlencode(build_query)
    build_payload = api_get(build_url, token)

    builds = []
    for build in build_payload.get("data", []):
        attributes = build.get("attributes", {})
        builds.append({
            "id": build.get("id"),
            "version": attributes.get("version"),
            "uploadedDate": attributes.get("uploadedDate"),
            "processingState": attributes.get("processingState"),
            "buildAudienceType": attributes.get("buildAudienceType"),
            "expired": attributes.get("expired"),
            "minOsVersion": attributes.get("minOsVersion"),
            "computedMinMacOsVersion": attributes.get("computedMinMacOsVersion")
        })

    result = {
        "ok": True,
        "bundleId": bundle_id,
        "app": {
            "id": app_id,
            "name": app.get("attributes", {}).get("name"),
            "sku": app.get("attributes", {}).get("sku"),
            "bundleId": app.get("attributes", {}).get("bundleId")
        },
        "builds": builds
    }
    print(json.dumps(result))
except urllib.error.HTTPError as exc:
    print(json.dumps({
        "ok": False,
        "error": "HTTP_ERROR",
        "status": exc.code,
        "body": exc.read().decode('utf-8', errors='replace')
    }))
"@

  $result = $pythonScript | python -
  if ($LASTEXITCODE -ne 0) {
    throw "TestFlight status check failed."
  }

  return ($result | ConvertFrom-Json)
}

function Write-StatusSummary {
  param([Parameter(Mandatory)]$Payload)

  Write-Host ("Bundle ID: " + $Payload.bundleId)
  Write-Host ("App: " + $Payload.app.name + " | " + $Payload.app.sku + " | " + $Payload.app.id)

  if (-not $Payload.builds -or $Payload.builds.Count -eq 0) {
    Write-Host "Builds: 0"
    return
  }

  Write-Host ("Builds: " + $Payload.builds.Count)
  $index = 0
  foreach ($build in $Payload.builds) {
    $index += 1
    $line = "#{0}: build {1} | state={2} | audience={3} | uploaded={4}" -f $index, $build.version, $build.processingState, $build.buildAudienceType, $build.uploadedDate
    Write-Host $line
  }
}

Assert-Prerequisites

$terminalStates = @("VALID", "FAILED", "INVALID", "PROCESSING_EXCEPTION")
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

do {
  $payload = Get-TestFlightStatus

  if (-not $payload.ok) {
    if ($Json) {
      $payload | ConvertTo-Json -Depth 8
    } elseif ($payload.error -eq "APP_NOT_FOUND") {
      Write-Host ("Bundle ID not found in App Store Connect: " + $payload.bundleId)
    } else {
      Write-Host ("API error: " + $payload.error)
      if ($payload.status) {
        Write-Host ("Status: " + $payload.status)
      }
      if ($payload.body) {
        Write-Host $payload.body
      }
    }
    exit 1
  }

  if ($Json) {
    $payload | ConvertTo-Json -Depth 8
  } else {
    Write-StatusSummary -Payload $payload
  }

  $latestBuild = if ($payload.builds -and $payload.builds.Count -gt 0) { $payload.builds[0] } else { $null }
  $done = $false

  if (-not $WaitUntilProcessed) {
    $done = $true
  } elseif (-not $latestBuild) {
    if ((Get-Date) -ge $deadline) {
      throw "No builds appeared before timeout."
    }
    Write-Host ("Waiting for first build to appear. Next check in " + $PollIntervalSeconds + "s.")
    Start-Sleep -Seconds $PollIntervalSeconds
  } elseif ($terminalStates -contains $latestBuild.processingState) {
    $done = $true
  } elseif ((Get-Date) -ge $deadline) {
    throw ("Timed out waiting for build processing. Latest state: " + $latestBuild.processingState)
  } else {
    Write-Host ("Waiting for build " + $latestBuild.version + " to finish processing. Next check in " + $PollIntervalSeconds + "s.")
    Start-Sleep -Seconds $PollIntervalSeconds
  }
} until ($done)
