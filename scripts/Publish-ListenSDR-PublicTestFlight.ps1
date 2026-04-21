param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$InfoPlistPath,
  [string]$MarketingVersion,
  [string]$BuildVersion,
  [string]$PublicBetaGroupName = "publiczna",
  [string]$PublicBetaGroupId = "f4e0a82c-19ea-4aa2-aaef-fe0d930d4126",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-DefaultAscApiKeyPath {
  param([string]$CurrentValue)

  $candidates = @(
    $CurrentValue,
    "C:\Users\Kazek\Desktop\Mac i logowanie\AuthKey_RDRPTFY7U4.p8",
    "C:\Users\Kazek\Desktop\iOS\AuthKey_RDRPTFY7U4.p8"
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $CurrentValue
}

function Get-ReleaseInfoFromInfoPlist {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Info.plist not found: $Path"
  }

  $content = Get-Content $Path -Raw
  $shortVersionMatch = [regex]::Match($content, '<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>')
  $buildVersionMatch = [regex]::Match($content, '<key>CFBundleVersion</key>\s*<string>([^<]+)</string>')

  if (-not $shortVersionMatch.Success -or -not $buildVersionMatch.Success) {
    throw "Unable to read CFBundleShortVersionString or CFBundleVersion from Info.plist."
  }

  return @{
    MarketingVersion = $shortVersionMatch.Groups[1].Value.Trim()
    BuildVersion = $buildVersionMatch.Groups[1].Value.Trim()
  }
}

if ([string]::IsNullOrWhiteSpace($InfoPlistPath)) {
  $InfoPlistPath = Join-Path $RepoRoot "native-ios\ListenSDR\Info.plist"
}

$AscApiKeyPath = Resolve-DefaultAscApiKeyPath -CurrentValue $AscApiKeyPath
if ([string]::IsNullOrWhiteSpace($AscApiKeyPath) -or -not (Test-Path $AscApiKeyPath)) {
  throw "ASC API key file not found."
}
if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
  throw "ASC key ID or issuer ID is missing."
}

$releaseInfo = Get-ReleaseInfoFromInfoPlist -Path $InfoPlistPath
if ([string]::IsNullOrWhiteSpace($MarketingVersion)) {
  $MarketingVersion = $releaseInfo.MarketingVersion
}
if ([string]::IsNullOrWhiteSpace($BuildVersion)) {
  $BuildVersion = $releaseInfo.BuildVersion
}

$tempPythonPath = Join-Path $env:TEMP ("ListenSDR-PublicTestFlight-{0}.py" -f [guid]::NewGuid().ToString("N"))
$tempOutputPath = Join-Path $env:TEMP ("ListenSDR-PublicTestFlight-{0}.json" -f [guid]::NewGuid().ToString("N"))
try {
  $pythonScript = @"
import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

key_path = Path(r'''$AscApiKeyPath''')
key_id = r'''$AscKeyId'''
issuer_id = r'''$AscIssuerId'''
bundle_id = r'''$BundleId'''
marketing_version = r'''$MarketingVersion'''
build_version = r'''$BuildVersion'''
public_group_name = r'''$PublicBetaGroupName'''
public_group_id = r'''$PublicBetaGroupId'''

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
base_url = "https://api.appstoreconnect.apple.com/v1"

def api_request(method: str, url: str, body=None):
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        payload = json.loads(raw) if raw else {}
        return exc.code, payload

def api_get(url: str):
    return api_request("GET", url)

status, app_payload = api_get(f"{base_url}/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle_id}))
apps = app_payload.get("data", [])
if not apps:
    raise RuntimeError(f"Bundle ID not found in App Store Connect: {bundle_id}")
app = apps[0]
app_id = app["id"]

status, build_payload = api_get(
    f"{base_url}/builds?" + urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[version]": build_version,
        "sort": "-uploadedDate",
        "limit": "20",
    })
)
builds = build_payload.get("data", [])
if not builds:
    raise RuntimeError(f"Build {build_version} not found for bundle {bundle_id}.")
build = builds[0]
build_id = build["id"]

group_query = urllib.parse.urlencode({"filter[app]": app_id, "limit": "200"})
status, group_payload = api_get(f"{base_url}/betaGroups?{group_query}")
groups = group_payload.get("data", [])

selected_group = None
for group in groups:
    if public_group_id and group["id"] == public_group_id:
        selected_group = group
        break

if selected_group is None:
    def normalize(text: str) -> str:
        return (text or "").strip().casefold()
    for group in groups:
        if normalize(group["attributes"].get("name")) == normalize(public_group_name):
            selected_group = group
            break

if selected_group is None:
    raise RuntimeError(f"Public beta group not found: {public_group_name}")

group_id = selected_group["id"]

attach_status, attach_payload = api_request(
    "POST",
    f"{base_url}/betaGroups/{group_id}/relationships/builds",
    {
        "data": [
            {
                "type": "builds",
                "id": build_id,
            }
        ]
    },
)
attached = attach_status in (200, 201, 204, 409)

status, beta_detail_payload = api_get(f"{base_url}/builds/{build_id}/buildBetaDetail")
beta_detail = beta_detail_payload.get("data")
external_state = None
if beta_detail is not None:
    external_state = beta_detail.get("attributes", {}).get("externalBuildState")

status, submission_payload = api_get(f"{base_url}/builds/{build_id}/betaAppReviewSubmission")
existing_submission = submission_payload.get("data")

submission_action = "not_needed"
submission_result = None

if existing_submission is not None:
    submission_action = "already_exists"
    submission_result = existing_submission
elif external_state == "READY_FOR_BETA_SUBMISSION":
    post_status, post_payload = api_request(
        "POST",
        f"{base_url}/betaAppReviewSubmissions",
        {
            "data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {
                    "build": {
                        "data": {
                            "type": "builds",
                            "id": build_id,
                        }
                    }
                },
            }
        },
    )
    if post_status in (200, 201):
        submission_action = "submitted"
        submission_result = post_payload.get("data")
    else:
        submission_action = "submit_failed"
        submission_result = post_payload

result = {
    "bundleId": bundle_id,
    "marketingVersion": marketing_version,
    "buildVersion": build_version,
    "buildId": build_id,
    "processingState": build.get("attributes", {}).get("processingState"),
    "externalBuildState": external_state,
    "groupId": group_id,
    "groupName": selected_group["attributes"].get("name"),
    "publicLink": selected_group["attributes"].get("publicLink"),
    "publicLinkEnabled": selected_group["attributes"].get("publicLinkEnabled"),
    "attached": attached,
    "attachStatus": attach_status,
    "submissionAction": submission_action,
    "submissionResult": submission_result,
}

Path(r'''$tempOutputPath''').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
"@

  Set-Content -Path $tempPythonPath -Value $pythonScript -Encoding UTF8
  & python $tempPythonPath
  if ($LASTEXITCODE -ne 0) {
    throw "Public TestFlight publish script failed."
  }

  $result = Get-Content $tempOutputPath -Raw | ConvertFrom-Json
  if ($Json) {
    $result | ConvertTo-Json -Depth 10
  } else {
    Write-Host ("Bundle ID: " + $result.bundleId)
    Write-Host ("Version: " + $result.marketingVersion + " (" + $result.buildVersion + ")")
    Write-Host ("Build ID: " + $result.buildId)
    Write-Host ("Processing state: " + $result.processingState)
    Write-Host ("External state: " + $result.externalBuildState)
    Write-Host ("Group: " + $result.groupName + " [" + $result.groupId + "]")
    Write-Host ("Attached to group: " + $result.attached)
    Write-Host ("Submission action: " + $result.submissionAction)
    Write-Host ("Public link: " + $result.publicLink)
  }
} finally {
  Remove-Item $tempPythonPath -ErrorAction SilentlyContinue
  Remove-Item $tempOutputPath -ErrorAction SilentlyContinue
}
