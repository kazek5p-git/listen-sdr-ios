$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectFile = Join-Path $repoRoot "native-ios\project.yml"
$configFile = Join-Path $repoRoot "native-ios\ListenSDR\Resources\GoogleService-Info.plist"
$bootstrapFile = Join-Path $repoRoot "native-ios\ListenSDR\Sources\FirebaseBootstrap.swift"

function Test-FileContains {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Description
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }

  $content = Get-Content -Raw -LiteralPath $Path
  if ($content -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

Test-FileContains -Path $projectFile -Pattern "firebase-ios-sdk" -Description "Firebase Swift Package dependency"
Test-FileContains -Path $projectFile -Pattern "FirebaseCore" -Description "FirebaseCore product dependency"
Test-FileContains -Path $projectFile -Pattern "FirebaseCrashlytics" -Description "FirebaseCrashlytics product dependency"
Test-FileContains -Path $projectFile -Pattern "FirebaseRemoteConfig" -Description "FirebaseRemoteConfig product dependency"
Test-FileContains -Path $projectFile -Pattern "Crashlytics/run" -Description "Crashlytics dSYM upload script"
Test-FileContains -Path $projectFile -Pattern "LISTENSDR_CRASHLYTICS_UPLOAD_SYMBOLS" -Description "Crashlytics dSYM upload build flag"
Test-FileContains -Path $projectFile -Pattern "LISTENSDR_FIREBASE_CRASHLYTICS_ENABLED" -Description "Crashlytics collection build flag"
Test-FileContains -Path $projectFile -Pattern "DWARF_DSYM_FOLDER_PATH" -Description "Crashlytics dSYM input files"
Test-FileContains -Path $bootstrapFile -Pattern "FirebaseBootstrap" -Description "Firebase bootstrap source"

if (Test-Path -LiteralPath $configFile) {
  [xml]$plist = Get-Content -Raw -LiteralPath $configFile
  $dict = $plist.plist.dict
  $values = @{}

  for ($i = 0; $i -lt $dict.ChildNodes.Count; $i += 2) {
    $key = $dict.ChildNodes[$i].InnerText
    $valueNode = $dict.ChildNodes[$i + 1]
    $values[$key] = $valueNode.InnerText
  }

  if ($values["BUNDLE_ID"] -ne "com.kazek.sdr") {
    throw "GoogleService-Info.plist has unexpected BUNDLE_ID: $($values["BUNDLE_ID"])"
  }
  if ($values["PROJECT_ID"] -ne "listen-sdr-kazek5p") {
    throw "GoogleService-Info.plist has unexpected PROJECT_ID: $($values["PROJECT_ID"])"
  }
  if ([string]::IsNullOrWhiteSpace($values["GOOGLE_APP_ID"])) {
    throw "GoogleService-Info.plist is missing GOOGLE_APP_ID."
  }

  Write-Host "OK: GoogleService-Info.plist is present for listen-sdr-kazek5p / com.kazek.sdr."
} else {
  Write-Warning "GoogleService-Info.plist is not present. The app will run with Firebase disabled until the file is added."
}

Write-Host "OK: Listen SDR Firebase project wiring is present."
