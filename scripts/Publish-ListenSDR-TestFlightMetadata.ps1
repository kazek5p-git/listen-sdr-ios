param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$BundleId = "com.kazek.sdr",
  [string]$AscApiKeyPath = [Environment]::GetEnvironmentVariable("EXPO_ASC_API_KEY_PATH", "User"),
  [string]$AscKeyId = [Environment]::GetEnvironmentVariable("EXPO_ASC_KEY_ID", "User"),
  [string]$AscIssuerId = [Environment]::GetEnvironmentVariable("EXPO_ASC_ISSUER_ID", "User"),
  [string]$InfoPlistPath,
  [string]$ReleaseNotesRoot,
  [string]$MarketingVersion,
  [string]$BuildVersion,
  [string]$BetaGroupName = "wewnetrzna",
  [string]$BetaGroupId = "89359342-cf9d-480b-9c75-8e34a7fef728",
  [switch]$ValidateOnly,
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

function Get-ReleaseNotesDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$MarketingVersion,
    [Parameter(Mandatory = $true)][string]$BuildVersion
  )

  return Join-Path $Root ("{0}-build-{1}" -f $MarketingVersion, $BuildVersion)
}

function Get-ReleaseNotesPayload {
  param([Parameter(Mandatory = $true)][string]$DirectoryPath)

  $noteFiles = @(
    @{ Locale = "pl"; Path = (Join-Path $DirectoryPath "what-to-test.pl.txt") },
    @{ Locale = "en-US"; Path = (Join-Path $DirectoryPath "what-to-test.en-US.txt") }
  )

  $localizations = @()
  foreach ($noteFile in $noteFiles) {
    if (-not (Test-Path $noteFile.Path)) {
      throw "Release notes file not found: $($noteFile.Path)"
    }

    $content = [System.IO.File]::ReadAllText($noteFile.Path, [System.Text.Encoding]::UTF8)
    if ($null -eq $content) {
      $content = ""
    }
    $content = $content.TrimStart([char]0xFEFF).Trim()
    if ([string]::IsNullOrWhiteSpace($content)) {
      throw "Release notes file is empty: $($noteFile.Path)"
    }

    $localizations += @{
      locale = $noteFile.Locale
      whatsNew = $content
    }
  }

  return $localizations
}

function Assert-Prerequisites {
  param(
    [string]$ResolvedAscApiKeyPath,
    [switch]$SkipAscChecks
  )

  if ($SkipAscChecks) {
    return
  }

  if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python is not available in PATH."
  }
  if ([string]::IsNullOrWhiteSpace($ResolvedAscApiKeyPath) -or -not (Test-Path $ResolvedAscApiKeyPath)) {
    throw "ASC API key file not found."
  }
  if ([string]::IsNullOrWhiteSpace($AscKeyId) -or [string]::IsNullOrWhiteSpace($AscIssuerId)) {
    throw "ASC key ID or issuer ID is missing."
  }
}

if ([string]::IsNullOrWhiteSpace($InfoPlistPath)) {
  $InfoPlistPath = Join-Path $RepoRoot "native-ios\ListenSDR\Info.plist"
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotesRoot)) {
  $ReleaseNotesRoot = Join-Path $RepoRoot "release\testflight"
}

$AscApiKeyPath = Resolve-DefaultAscApiKeyPath -CurrentValue $AscApiKeyPath
Assert-Prerequisites -ResolvedAscApiKeyPath $AscApiKeyPath -SkipAscChecks:$ValidateOnly

$releaseInfo = Get-ReleaseInfoFromInfoPlist -Path $InfoPlistPath
if ([string]::IsNullOrWhiteSpace($MarketingVersion)) {
  $MarketingVersion = $releaseInfo.MarketingVersion
}
if ([string]::IsNullOrWhiteSpace($BuildVersion)) {
  $BuildVersion = $releaseInfo.BuildVersion
}

$releaseNotesDirectory = Get-ReleaseNotesDirectory -Root $ReleaseNotesRoot -MarketingVersion $MarketingVersion -BuildVersion $BuildVersion
$localizations = Get-ReleaseNotesPayload -DirectoryPath $releaseNotesDirectory

if ($ValidateOnly) {
  $validationResult = [pscustomobject]@{
    ok = $true
    mode = "validate-only"
    bundleId = $BundleId
    marketingVersion = $MarketingVersion
    buildVersion = $BuildVersion
    releaseNotesDirectory = $releaseNotesDirectory
    locales = @($localizations | ForEach-Object { $_.locale })
    localizationLengths = @(
      $localizations | ForEach-Object {
        [pscustomobject]@{
          locale = $_.locale
          length = $_.whatsNew.Length
        }
      }
    )
  }

  if ($Json) {
    $validationResult | ConvertTo-Json -Depth 8
  } else {
    Write-Host ("Bundle ID: " + $validationResult.bundleId)
    Write-Host ("Version: " + $validationResult.marketingVersion + " (" + $validationResult.buildVersion + ")")
    Write-Host ("Release notes directory: " + $validationResult.releaseNotesDirectory)
    foreach ($item in $validationResult.localizationLengths) {
      Write-Host ("Locale " + $item.locale + ": validated (" + $item.length + " chars)")
    }
  }
  exit 0
}

$requestPayload = @{
  bundleId = $BundleId
  marketingVersion = $MarketingVersion
  buildVersion = $BuildVersion
  betaGroupName = $BetaGroupName
  betaGroupId = $BetaGroupId
  releaseNotesDirectory = $releaseNotesDirectory
  localizations = $localizations
}

$tempInputPath = Join-Path $env:TEMP ("ListenSDR-TestFlightMetadata-{0}.json" -f [guid]::NewGuid().ToString("N"))
$tempPythonPath = Join-Path $env:TEMP ("ListenSDR-TestFlightMetadata-{0}.py" -f [guid]::NewGuid().ToString("N"))
$tempErrorPath = Join-Path $env:TEMP ("ListenSDR-TestFlightMetadata-{0}.stderr.txt" -f [guid]::NewGuid().ToString("N"))
try {
  $requestPayload | ConvertTo-Json -Depth 6 | Set-Content -Path $tempInputPath -Encoding utf8

  $pythonScript = @"
import base64
import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path
import unicodedata

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

input_path = Path(r'''$tempInputPath''')
key_path = Path(r'''$AscApiKeyPath''')
key_id = r'''$AscKeyId'''
issuer_id = r'''$AscIssuerId'''

payload = json.loads(input_path.read_text(encoding='utf-8-sig'))
bundle_id = payload["bundleId"]
marketing_version = payload["marketingVersion"]
build_version = payload["buildVersion"]
beta_group_name = payload["betaGroupName"]
beta_group_id = payload.get("betaGroupId", "")
release_notes_directory = payload["releaseNotesDirectory"]
localizations = payload["localizations"]

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
    with urllib.request.urlopen(request, timeout=60) as response:
        raw = response.read().decode("utf-8")
        return response.status, json.loads(raw) if raw else {}

def api_get(url: str):
    return api_request("GET", url)[1]

base_url = "https://api.appstoreconnect.apple.com/v1"

try:
    app_query = urllib.parse.urlencode({"filter[bundleId]": bundle_id})
    app_payload = api_get(f"{base_url}/apps?{app_query}")
    apps = app_payload.get("data", [])
    if not apps:
        raise RuntimeError(f"Bundle ID not found in App Store Connect: {bundle_id}")

    app = apps[0]
    app_id = app["id"]

    build_query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[version]": build_version,
        "sort": "-uploadedDate",
        "limit": "20",
    })
    build_payload = api_get(f"{base_url}/builds?{build_query}")
    builds = build_payload.get("data", [])
    if not builds:
        raise RuntimeError(f"Build {build_version} not found for bundle {bundle_id}.")

    build = builds[0]
    build_id = build["id"]

    existing_loc_payload = api_get(f"{base_url}/builds/{build_id}/betaBuildLocalizations?limit=200")
    existing_by_locale = {}
    for item in existing_loc_payload.get("data", []):
        existing_by_locale[item["attributes"]["locale"]] = item

    localization_actions = []
    for localization in localizations:
        locale = localization["locale"]
        whats_new = localization["whatsNew"].strip()
        existing = existing_by_locale.get(locale)

        if existing is None:
            _, created = api_request(
                "POST",
                f"{base_url}/betaBuildLocalizations",
                {
                    "data": {
                        "type": "betaBuildLocalizations",
                        "attributes": {
                            "locale": locale,
                            "whatsNew": whats_new,
                        },
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
            localization_actions.append({
                "locale": locale,
                "action": "created",
                "id": created["data"]["id"],
            })
            continue

        existing_text = existing["attributes"].get("whatsNew", "")
        if existing_text != whats_new:
            _, updated = api_request(
                "PATCH",
                f"{base_url}/betaBuildLocalizations/{existing['id']}",
                {
                    "data": {
                        "type": "betaBuildLocalizations",
                        "id": existing["id"],
                        "attributes": {
                            "whatsNew": whats_new,
                        },
                    }
                },
            )
            localization_actions.append({
                "locale": locale,
                "action": "updated",
                "id": updated["data"]["id"],
            })
        else:
            localization_actions.append({
                "locale": locale,
                "action": "unchanged",
                "id": existing["id"],
            })

    beta_groups_payload = api_get(f"{base_url}/apps/{app_id}/betaGroups?limit=200")

    def normalize_name(value: str) -> str:
        normalized = unicodedata.normalize("NFKD", value or "")
        return normalized.encode("ascii", "ignore").decode("ascii").casefold()

    matching_group = None
    for item in beta_groups_payload.get("data", []):
        if beta_group_id and item.get("id") == beta_group_id:
            matching_group = item
            break

    if matching_group is None:
        wanted_name = normalize_name(beta_group_name)
        for item in beta_groups_payload.get("data", []):
            current_name = item.get("attributes", {}).get("name", "")
            if current_name == beta_group_name or normalize_name(current_name) == wanted_name:
                matching_group = item
                break

    if matching_group is None:
        raise RuntimeError(f"Beta group not found: {beta_group_name} ({beta_group_id})")

    group_id = matching_group["id"]
    build_groups_payload = api_get(f"{base_url}/betaGroups/{group_id}/builds?limit=200")
    attached_group_ids = {item["id"] for item in build_groups_payload.get("data", [])}

    if build_id in attached_group_ids:
        group_action = "already_attached"
    else:
        api_request(
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
        group_action = "attached"

    final_localizations_payload = api_get(f"{base_url}/builds/{build_id}/betaBuildLocalizations?limit=200")
    whats_new_by_locale = {}
    final_locales = []
    for item in final_localizations_payload.get("data", []):
        locale = item["attributes"]["locale"]
        final_locales.append(locale)
        whats_new_by_locale[locale] = item["attributes"].get("whatsNew", "")

    result = {
        "ok": True,
        "bundleId": bundle_id,
        "marketingVersion": marketing_version,
        "buildVersion": build_version,
        "buildId": build_id,
        "betaGroupName": matching_group.get("attributes", {}).get("name", beta_group_name),
        "betaGroupId": group_id,
        "betaGroupAction": group_action,
        "releaseNotesDirectory": release_notes_directory,
        "localizationActions": localization_actions,
        "locales": sorted(final_locales),
        "whatsNewByLocale": whats_new_by_locale,
    }
    print(json.dumps(result, ensure_ascii=False))
except urllib.error.HTTPError as exc:
    print(json.dumps({
        "ok": False,
        "error": "HTTP_ERROR",
        "status": exc.code,
        "body": exc.read().decode("utf-8", errors="replace"),
    }, ensure_ascii=False))
    sys.exit(1)
except Exception as exc:
    print(json.dumps({
        "ok": False,
        "error": "RUNTIME_ERROR",
        "message": str(exc),
    }, ensure_ascii=False))
    sys.exit(1)
"@

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tempPythonPath, $pythonScript, $utf8NoBom)

  $rawResult = & python $tempPythonPath 2> $tempErrorPath
  $rawResultText = ""
  if ($null -ne $rawResult) {
    $rawResultText = ($rawResult | Out-String).Trim()
  }
  $stderr = ""
  if (Test-Path $tempErrorPath) {
    $stderrContent = Get-Content $tempErrorPath -Raw
    if ($null -ne $stderrContent) {
      $stderr = $stderrContent.Trim()
    }
  }

  if ([string]::IsNullOrWhiteSpace($rawResultText)) {
    if ($LASTEXITCODE -ne 0 -and -not [string]::IsNullOrWhiteSpace($stderr)) {
      throw ("TestFlight metadata publish failed.`n" + $stderr)
    }
    if ($LASTEXITCODE -ne 0) {
      throw "TestFlight metadata publish failed."
    }
    throw "TestFlight metadata publish returned no output."
  }

  try {
    $result = $rawResultText | ConvertFrom-Json
  } catch {
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
      throw ("TestFlight metadata publish failed.`n" + $stderr)
    }
    throw ("TestFlight metadata publish returned invalid JSON.`n" + $rawResultText)
  }

  if (-not $result.ok) {
    if ($Json) {
      $result | ConvertTo-Json -Depth 8
    } else {
      Write-Host ("API error: " + $result.error)
      if ($result.status) {
        Write-Host ("Status: " + $result.status)
      }
      if ($result.message) {
        Write-Host ("Message: " + $result.message)
      }
      if ($result.body) {
        Write-Host $result.body
      }
    }
    exit 1
  }

  if ($Json) {
    $result | ConvertTo-Json -Depth 8
  } else {
    Write-Host ("Bundle ID: " + $result.bundleId)
    Write-Host ("Version: " + $result.marketingVersion + " (" + $result.buildVersion + ")")
    Write-Host ("Build ID: " + $result.buildId)
    Write-Host ("Beta group: " + $result.betaGroupName + " | " + $result.betaGroupAction)
    foreach ($action in $result.localizationActions) {
      Write-Host ("Locale " + $action.locale + ": " + $action.action)
    }
    Write-Host ("Locales on build: " + ($result.locales -join ", "))
  }
} finally {
  if (Test-Path $tempInputPath) {
    Remove-Item $tempInputPath -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $tempPythonPath) {
    Remove-Item $tempPythonPath -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path $tempErrorPath) {
    Remove-Item $tempErrorPath -Force -ErrorAction SilentlyContinue
  }
}
