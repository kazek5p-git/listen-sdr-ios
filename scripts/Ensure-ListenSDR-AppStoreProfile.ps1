param(
  [string]$BundleId = "com.kazek.sdr",
  [string]$ProfileName = "ListenSDR_AppStore",
  [string]$ProfileOutputPath = (Join-Path $env:TEMP "ListenSDR_AppStore.mobileprovision"),
  [string]$AscApiKeyPath = "C:\Users\Kazek\Desktop\Mac i logowanie\AuthKey_RDRPTFY7U4.p8",
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
import base64, json, time, urllib.parse, urllib.request, urllib.error
from pathlib import Path
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils

bundle_id = r'''$BundleId'''
profile_name = r'''$ProfileName'''
output_path = Path(r'''$ProfileOutputPath''')
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
headers = {"Authorization": f"Bearer {jwt_token}", "Accept": "application/json"}

def api_get(path, query=None):
    url = "https://api.appstoreconnect.apple.com" + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))

def api_post(path, payload):
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path,
        data=body,
        method="POST",
        headers={**headers, "Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))

bundle_payload = api_get("/v1/bundleIds", {"filter[identifier]": bundle_id, "limit": "20"})
bundle_ids = bundle_payload.get("data", [])
if not bundle_ids:
    raise SystemExit(json.dumps({"ok": False, "error": f"Bundle ID not found: {bundle_id}"}))
bundle = bundle_ids[0]

certificate_payload = api_get("/v1/certificates", {"filter[certificateType]": "DISTRIBUTION", "limit": "50"})
certificates = certificate_payload.get("data", [])
if not certificates:
    raise SystemExit(json.dumps({"ok": False, "error": "No DISTRIBUTION certificate found in Apple Developer."}))
certificate = certificates[0]

profiles_payload = api_get(f"/v1/bundleIds/{bundle['id']}/profiles", {"limit": "50"})
profiles = profiles_payload.get("data", [])
profile = None
for candidate in profiles:
    attrs = candidate.get("attributes", {})
    if attrs.get("profileState") == "ACTIVE" and attrs.get("profileType") == "IOS_APP_STORE":
        profile = candidate
        break

if profile is None:
    profile = api_post(
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {
                    "name": profile_name,
                    "profileType": "IOS_APP_STORE"
                },
                "relationships": {
                    "bundleId": {
                        "data": {"type": "bundleIds", "id": bundle["id"]}
                    },
                    "certificates": {
                        "data": [{"type": "certificates", "id": certificate["id"]}]
                    }
                }
            }
        }
    )["data"]

profile_id = profile["id"]
profile_detail = api_get(f"/v1/profiles/{profile_id}")["data"]
attrs = profile_detail["attributes"]
profile_content = base64.b64decode(attrs["profileContent"])
output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_bytes(profile_content)

result = {
    "ok": True,
    "bundleId": bundle_id,
    "bundleResourceId": bundle["id"],
    "certificateId": certificate["id"],
    "certificateName": certificate.get("attributes", {}).get("name"),
    "profileId": profile_id,
    "profileName": attrs["name"],
    "profileUuid": attrs["uuid"],
    "profilePath": str(output_path),
}
print(json.dumps(result))
"@

$rawResult = $script | python -
if ($LASTEXITCODE -ne 0) {
  throw "Failed to ensure App Store provisioning profile."
}

$result = $rawResult | ConvertFrom-Json
if (-not $result.ok) {
  throw $result.error
}

$result | ConvertTo-Json -Compress | Write-Output
