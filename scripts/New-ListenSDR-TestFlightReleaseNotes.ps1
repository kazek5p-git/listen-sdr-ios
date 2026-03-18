param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$InfoPlistPath,
  [string]$ReleaseNotesRoot,
  [string]$MarketingVersion,
  [int]$BuildVersion,
  [string]$SourceDirectory,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

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
    BuildVersion = [int]$buildVersionMatch.Groups[1].Value.Trim()
  }
}

function Get-ReleaseDirectoryName {
  param(
    [Parameter(Mandatory = $true)][string]$MarketingVersion,
    [Parameter(Mandatory = $true)][int]$BuildVersion
  )

  return "{0}-build-{1}" -f $MarketingVersion, $BuildVersion
}

function Get-LatestReleaseNotesDirectory {
  param([Parameter(Mandatory = $true)][string]$Root)

  if (-not (Test-Path $Root)) {
    return $null
  }

  $directories = Get-ChildItem -Path $Root -Directory | Sort-Object Name
  if (-not $directories) {
    return $null
  }

  return $directories[-1].FullName
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if ([string]::IsNullOrWhiteSpace($InfoPlistPath)) {
  $InfoPlistPath = Join-Path $RepoRoot "native-ios\ListenSDR\Info.plist"
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotesRoot)) {
  $ReleaseNotesRoot = Join-Path $RepoRoot "release\testflight"
}

$releaseInfo = Get-ReleaseInfoFromInfoPlist -Path $InfoPlistPath
if ([string]::IsNullOrWhiteSpace($MarketingVersion)) {
  $MarketingVersion = $releaseInfo.MarketingVersion
}
if ($PSBoundParameters.ContainsKey("BuildVersion") -eq $false) {
  $BuildVersion = $releaseInfo.BuildVersion + 1
}

if (-not (Test-Path $ReleaseNotesRoot)) {
  New-Item -ItemType Directory -Path $ReleaseNotesRoot -Force | Out-Null
}

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
  $SourceDirectory = Get-LatestReleaseNotesDirectory -Root $ReleaseNotesRoot
}

$targetDirectory = Join-Path $ReleaseNotesRoot (Get-ReleaseDirectoryName -MarketingVersion $MarketingVersion -BuildVersion $BuildVersion)
if ((Test-Path $targetDirectory) -and -not $Force) {
  throw "Target directory already exists: $targetDirectory"
}

New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null

$files = @(
  @{ Name = "what-to-test.pl.txt"; Placeholder = "Uzupelnij polskie What to Test dla builda $BuildVersion." },
  @{ Name = "what-to-test.en-US.txt"; Placeholder = "Fill in the English What to Test for build $BuildVersion." }
)

foreach ($file in $files) {
  $targetPath = Join-Path $targetDirectory $file.Name
  $sourcePath = if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $null } else { Join-Path $SourceDirectory $file.Name }

  if ($sourcePath -and (Test-Path $sourcePath)) {
    $content = Get-Content $sourcePath -Raw
    if ($null -eq $content) {
      $content = ""
    }
    $content = $content.TrimStart([char]0xFEFF).TrimEnd()
  } else {
    $content = $file.Placeholder
  }

  Write-Utf8NoBomFile -Path $targetPath -Content ($content + [Environment]::NewLine)
}

$result = @{
  marketingVersion = $MarketingVersion
  buildVersion = $BuildVersion
  targetDirectory = $targetDirectory
  sourceDirectory = $SourceDirectory
  files = @(
    (Join-Path $targetDirectory "what-to-test.pl.txt"),
    (Join-Path $targetDirectory "what-to-test.en-US.txt")
  )
}

$result | ConvertTo-Json -Depth 5
