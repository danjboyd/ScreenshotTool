# Points a release job's copy of the manifest at the prerelease update channel (#111).
#
# Every build packages the manifest's updates.channel and each backend's feedUrl into the app's
# updater config, and GPUpdater reads only those: an rc built from the stable values checks
# stable.json and never sees prerelease.json. It also skips a feed whose "channel" differs from
# its own, so the build and the feed it writes have to change together, here. The AppImage's
# zsync update information uses GitHub's "latest" release, which skips prereleases; "latest-all"
# takes the newest release or prerelease, so an rc also moves on to the next stable.
#
# The release workflow runs this for prerelease tags only. Stable tags keep the manifest as is.
[CmdletBinding()]
param(
  [string]$ManifestPath = "packaging/package.manifest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw | ConvertFrom-Json -AsHashtable

$manifest["updates"]["channel"] = "prerelease"
foreach ($backend in @("msi", "appimage")) {
  $updates = $manifest["backends"][$backend]["updates"]
  $feedUrl = [string]$updates["feedUrl"]
  if ($feedUrl -notmatch '/stable\.json$') {
    throw "backends.$backend.updates.feedUrl doesn't end in /stable.json: $feedUrl"
  }
  $updates["feedUrl"] = $feedUrl -replace '/stable\.json$', '/prerelease.json'
}
$manifest["backends"]["appimage"]["updates"]["releaseSelector"] = "latest-all"

$manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifestFullPath -Encoding utf8NoBOM
Write-Host "Manifest set to the prerelease update channel:"
Write-Host "  updates.channel = $($manifest["updates"]["channel"])"
foreach ($backend in @("msi", "appimage")) {
  Write-Host "  backends.$backend.updates.feedUrl = $($manifest["backends"][$backend]["updates"]["feedUrl"])"
}
Write-Host "  backends.appimage.updates.releaseSelector = latest-all"
