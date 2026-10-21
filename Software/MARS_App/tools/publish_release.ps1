<#
Builds the MARS tablet app and publishes it as a GitHub release, so tablets can update from
"Check for updates" on the welcome screen.

  1. Raises the build number in pubspec.yaml (and sets a new version name if -Version is given)
  2. flutter build apk --release
  3. Writes release\<tag>\app-release.apk and version.json (version, build, APK link, size, SHA-256, notes)
  4. Uploads both as a GitHub release with the GitHub CLI (gh), if it is installed and logged in.
     Without gh it prints how to upload them on github.com instead.

The repository is the updateRepo constant in lib\core\updater.dart.

Run from PowerShell in Software\MARS_App:
  .\tools\publish_release.ps1 -Notes "Window mode controls, load-cell plot"
  .\tools\publish_release.ps1 -Version 1.2.0 -Notes "..."
#>
param(
    [Parameter(Mandatory = $true)][string]$Notes,
    [string]$Version = ""
)
$ErrorActionPreference = "Stop"
$app = Split-Path $PSScriptRoot -Parent
Set-Location $app
$utf8 = New-Object System.Text.UTF8Encoding $false  # no BOM: Dart's JSON reader and pubspec need plain UTF-8

# ---- Repository ----
$updater = [IO.File]::ReadAllText("$app\lib\core\updater.dart")
if ($updater -notmatch "const updateRepo = '([^']*)';") { throw "updateRepo not found in lib\core\updater.dart" }
$repo = $Matches[1]
if ($repo -eq "") { throw "Set updateRepo in lib\core\updater.dart first (e.g. 'yourname/mars-releases')" }

# ---- Version ----
$pubspecPath = "$app\pubspec.yaml"
$pubspec = [IO.File]::ReadAllText($pubspecPath)
if ($pubspec -notmatch "(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)") { throw "version: x.y.z+n not found in pubspec.yaml" }
$name = $Matches[1]
$build = [int]$Matches[2] + 1
if ($Version -ne "") {
    if ($Version -notmatch "^\d+\.\d+\.\d+$") { throw "-Version must look like 1.2.0" }
    $name = $Version
}
$pubspec = [regex]::Replace($pubspec, "(?m)^version:\s*\S+", "version: $name+$build")
[IO.File]::WriteAllText($pubspecPath, $pubspec, $utf8)
$tag = "v$name-b$build"
Write-Host "Version $name ($build), tag $tag, repository $repo" -ForegroundColor Cyan

# ---- Build ----
$env:PATH = "C:\dev\flutter\bin;$env:PATH"
$env:JAVA_TOOL_OPTIONS = "-Djava.net.preferIPv4Stack=true"   # Java downloads time out over IPv6 on this laptop
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "flutter build failed (pubspec.yaml already says $name+$build; that's fine, the next run raises it again)" }

# ---- Signature: tablets refuse ("App not installed") an update signed with another key ----
$keySha256 = "17f0d66c5209d0858fa245513b6de7e962f28def79971cfde6722f52d177f0a4"  # as in release-app.yml
$tools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory | Sort-Object Name | Select-Object -Last 1
$certs = & "$($tools.FullName)\apksigner.bat" verify --print-certs "$app\build\app\outputs\flutter-apk\app-release.apk"
$signed = ($certs | Select-String "certificate SHA-256 digest: (\w+)" | Select-Object -First 1).Matches.Groups[1].Value
if ($signed -ne $keySha256) { throw "The APK is signed with another key ($signed): tablets would refuse it. Nothing was published." }
Write-Host "Signed with the MARS key" -ForegroundColor Cyan

# ---- Release files ----
$out = "$app\release\$tag"
New-Item -ItemType Directory -Force $out | Out-Null
$apk = "$out\app-release.apk"
Copy-Item "$app\build\app\outputs\flutter-apk\app-release.apk" $apk -Force
$info = [ordered]@{
    version = $name
    build   = $build
    apk     = "https://github.com/$repo/releases/download/$tag/app-release.apk"
    size    = (Get-Item $apk).Length
    sha256  = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
    notes   = $Notes
}
[IO.File]::WriteAllText("$out\version.json", ($info | ConvertTo-Json), $utf8)
Write-Host "Release files: $out" -ForegroundColor Cyan

# ---- Upload ----
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    gh release create $tag "$apk" "$out\version.json" --repo $repo --title "MARS $name ($build)" --notes $Notes --latest
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed. The files are in $out; upload them by hand (see below)." }
    Write-Host "Published. Tablets get it from Check for updates." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "GitHub CLI (gh) not found. Upload by hand:" -ForegroundColor Yellow
    Write-Host "  1. Open https://github.com/$repo/releases/new"
    Write-Host "  2. Tag: $tag   (choose 'Create new tag')"
    Write-Host "  3. Title: MARS $name ($build)"
    Write-Host "  4. Drag in both files from $out : app-release.apk and version.json"
    Write-Host "  5. Keep 'Set as the latest release' ticked, then Publish release"
}
