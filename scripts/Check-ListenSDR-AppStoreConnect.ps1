param(
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User")
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  throw "python is not available in PATH."
}

if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) {
  throw "ASC API key file not found."
}
if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
  throw "ASC key ID or issuer ID is missing."
}

$script = @"
import base64, json, sys, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils

bundle_id = r'''$BundleId'''
key_path = Path(r'''$AscApiKeyPath''')
key_id = r'''$AscKeyId'''
issuer_id = r'''$AscIssuerId'''

private_key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')

header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
now = int(time.time())
payload = {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
signing_input = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
der_sig = private_key.sign(signing_input.encode('ascii'), ec.ECDSA(hashes.SHA256()))
r, s = utils.decode_dss_signature(der_sig)
raw_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
jwt_token = f"{signing_input}.{b64url(raw_sig)}"

url = "https://api.appstoreconnect.apple.com/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id})
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {jwt_token}", "Accept": "application/json"})

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode('utf-8'))
except urllib.error.HTTPError as exc:
    print(json.dumps({"ok": False, "status": exc.code, "body": exc.read().decode('utf-8')}))
    sys.exit(0)

apps = payload.get("data", [])
result = {
    "ok": True,
    "bundleId": bundle_id,
    "count": len(apps),
    "apps": [
        {
            "id": app.get("id"),
            "name": app.get("attributes", {}).get("name"),
            "sku": app.get("attributes", {}).get("sku"),
            "bundleId": app.get("attributes", {}).get("bundleId")
        }
        for app in apps
    ]
}
print(json.dumps(result))
"@

$result = $script | python -
if ($LASTEXITCODE -ne 0) {
  throw "App Store Connect check failed."
}

$payload = $result | ConvertFrom-Json

if (-not $payload.ok) {
  Write-Host ("API error status: " + $payload.status)
  Write-Host $payload.body
  exit 1
}

Write-Host ("Bundle ID: " + $payload.bundleId)
Write-Host ("Matching apps: " + $payload.count)
if ($payload.count -gt 0) {
  $payload.apps | ForEach-Object {
    Write-Host ("- " + $_.name + " | " + $_.sku + " | " + $_.id)
  }
}
