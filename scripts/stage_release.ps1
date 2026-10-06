[CmdletBinding()]
param(
  [string]$ManifestPath = "packaging/package.manifest.json",
  [string]$StageRoot = "dist/stage",
  [string]$PackageVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))
$resolvedStageRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $StageRoot))
$appSourceRoot = Join-Path $repoRoot "ScreenshotTool.app"
$appStageRoot = Join-Path $resolvedStageRoot "app\ScreenshotTool.app"
$runtimeRoot = Join-Path $resolvedStageRoot "runtime"
$metadataRoot = Join-Path $resolvedStageRoot "metadata"
$metadataIconRoot = Join-Path $metadataRoot "icons"
$metadataLicenseRoot = Join-Path $metadataRoot "licenses"
$stageLogRoot = Join-Path $resolvedStageRoot "logs"
$linuxExcludedLibraries = @(
  "linux-vdso.so.1",
  "libc.so.6",
  "libdl.so.2",
  "libm.so.6",
  "libpthread.so.0",
  "librt.so.1",
  "ld-linux-x86-64.so.2"
)

function Reset-Directory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (Test-Path $Path) {
    Remove-Item -Recurse -Force $Path
  }
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Ensure-Directory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  New-Item -ItemType Directory -Force -Path $Path | Out-Null
  return $Path
}

function Write-StageLog {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Ensure-Directory -Path $stageLogRoot | Out-Null
  Add-Content -Path (Join-Path $stageLogRoot "stage.txt") -Value ("[{0}] {1}" -f (Get-Date).ToString("o"), $Message)
}

function Get-ManifestData {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path $Path)) {
    throw "Manifest not found: $Path"
  }

  return Get-Content -Raw -Path $Path | ConvertFrom-Json -AsHashtable
}

function Get-ReleaseVersion {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$Manifest,
    [string]$RequestedVersion
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedVersion)) {
    return [string]$RequestedVersion
  }
  if (-not [string]::IsNullOrWhiteSpace($env:GP_PACKAGE_VERSION_OVERRIDE)) {
    return [string]$env:GP_PACKAGE_VERSION_OVERRIDE
  }
  return [string]$Manifest["package"]["version"]
}

function Copy-DirectoryTree {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  if (-not (Test-Path $Source)) {
    return $false
  }

  Ensure-Directory -Path $Destination | Out-Null
  if ($IsLinux) {
    $command = "set -euo pipefail; cp -a ""$Source/."" ""$Destination/"""
    & /bin/bash -lc $command
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to copy directory tree: $Source -> $Destination"
    }
  } else {
    Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
  }

  return $true
}

function Copy-FileIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [Parameter(Mandatory = $true)]
    [string]$Destination
  )

  if (-not (Test-Path $Source)) {
    return $false
  }

  $sourceFullPath = [System.IO.Path]::GetFullPath($Source)
  $destinationFullPath = [System.IO.Path]::GetFullPath($Destination)
  if ($sourceFullPath.Equals($destinationFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  Ensure-Directory -Path (Split-Path -Parent $Destination) | Out-Null
  Copy-Item -Path $Source -Destination $Destination -Force
  return $true
}

function Copy-MatchingFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDirectory,
    [Parameter(Mandatory = $true)]
    [string[]]$Patterns,
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectory
  )

  if (-not (Test-Path $SourceDirectory)) {
    return 0
  }

  Ensure-Directory -Path $DestinationDirectory | Out-Null
  $copied = 0
  foreach ($pattern in $Patterns) {
    foreach ($file in Get-ChildItem -Path $SourceDirectory -Filter $pattern -File -ErrorAction SilentlyContinue) {
      Copy-Item -Path $file.FullName -Destination (Join-Path $DestinationDirectory $file.Name) -Force
      $copied += 1
    }
  }
  return $copied
}

function Get-AppBundleEntryPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot
  )

  $withoutExtension = Join-Path $BundleRoot "ScreenshotTool"
  if (Test-Path $withoutExtension) {
    return $withoutExtension
  }

  $withExe = Join-Path $BundleRoot "ScreenshotTool.exe"
  if (Test-Path $withExe) {
    return $withExe
  }

  throw "App bundle entry point not found under $BundleRoot."
}

function Normalize-StagedAppEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot
  )

  $withoutExtension = Join-Path $BundleRoot "ScreenshotTool"
  $withExe = Join-Path $BundleRoot "ScreenshotTool.exe"
  if ($IsWindows -and (Test-Path $withExe)) {
    Copy-Item -Path $withExe -Destination $withoutExtension -Force
  } elseif (-not (Test-Path $withoutExtension) -and (Test-Path $withExe)) {
    Copy-Item -Path $withExe -Destination $withoutExtension -Force
  }

  if (-not (Test-Path $withoutExtension)) {
    throw "Expected staged app entry is missing: $withoutExtension"
  }

  if ($IsLinux) {
    & chmod +x $withoutExtension
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to mark staged app entry executable: $withoutExtension"
    }
  }

  return $withoutExtension
}

function Resolve-UpdaterHelperSourcePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot
  )

  foreach ($candidate in @(
    (Join-Path $BundleRoot "gp-update-helper"),
    (Join-Path $BundleRoot "gp-update-helper.exe"),
    (Join-Path $RepoRoot "third_party\gnustep-packager-updater\objc\gp-update-helper\gp-update-helper"),
    (Join-Path $RepoRoot "third_party\gnustep-packager-updater\objc\gp-update-helper\gp-update-helper.exe")
  )) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Stage-UpdaterHelper {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot
  )

  $source = Resolve-UpdaterHelperSourcePath -RepoRoot $RepoRoot -BundleRoot $BundleRoot
  if ([string]::IsNullOrWhiteSpace($source)) {
    Write-Warning "gp-update-helper was not found in the build output or vendored updater tree."
    return
  }

  $helperPath = Join-Path $BundleRoot "gp-update-helper"
  [void](Copy-FileIfPresent -Source $source -Destination $helperPath)
  if ($IsWindows -or $source.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    [void](Copy-FileIfPresent -Source $source -Destination (Join-Path $BundleRoot "gp-update-helper.exe"))
  }

  if ($IsLinux) {
    & chmod +x $helperPath
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to mark staged updater helper executable: $helperPath"
    }
  }

  Write-StageLog "Staged updater helper from $source"
}

function Update-InfoPlistVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Version
  )

  if (-not (Test-Path $Path)) {
    return
  }

  $content = Get-Content -Raw -Path $Path
  foreach ($key in @(
    "ApplicationVersion",
    "ApplicationRelease",
    "FullVersionID",
    "Version",
    "CFBundleShortVersionString",
    "CFBundleVersion"
  )) {
    $pattern = "(?m)^(\s*$([regex]::Escape($key))\s*=\s*)""[^""]*"";"
    $replacement = ('$1"{0}";' -f $Version)
    $content = [regex]::Replace($content, $pattern, $replacement)
  }

  Set-Content -Path $Path -Value $content -Encoding utf8
}

function Update-StagedBundleVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BundleRoot,
    [Parameter(Mandatory = $true)]
    [string]$Version
  )

  foreach ($plistPath in @(
    (Join-Path $BundleRoot "Resources\Info-gnustep.plist"),
    (Join-Path $BundleRoot "Contents\Resources\Info-gnustep.plist")
  )) {
    Update-InfoPlistVersion -Path $plistPath -Version $Version
  }
}

function Get-LinuxDependencyEntries {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $entries = [System.Collections.Generic.List[psobject]]::new()
  $lines = & ldd $Path 2>$null
  if ($LASTEXITCODE -ne 0 -or $null -eq $lines) {
    return @()
  }

  foreach ($line in $lines) {
    if ($line -match '^\s*(\S+)\s+=>\s+(\S+)\s+\(') {
      $entries.Add([pscustomobject]@{
        Name = [string]$Matches[1]
        Path = [string]$Matches[2]
      }) | Out-Null
      continue
    }

    if ($line -match '^\s*(/[^ ]+)\s+\(') {
      $resolvedPath = [string]$Matches[1]
      $entries.Add([pscustomobject]@{
        Name = [System.IO.Path]::GetFileName($resolvedPath)
        Path = $resolvedPath
      }) | Out-Null
    }
  }

  return @($entries.ToArray())
}

function Get-LinuxElfRunpath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $lines = & readelf -d $Path 2>$null
  if ($LASTEXITCODE -ne 0 -or $null -eq $lines) {
    return $null
  }

  foreach ($line in $lines) {
    if ($line -match 'Library runpath:\s+\[(.+)\]') {
      return [string]$Matches[1]
    }
    if ($line -match 'Library rpath:\s+\[(.+)\]') {
      return [string]$Matches[1]
    }
  }

  return $null
}

function Patch-LinuxRunpathIfNeeded {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$NewRunpath
  )

  $existingRunpath = Get-LinuxElfRunpath -Path $Path
  if ([string]::IsNullOrWhiteSpace($existingRunpath)) {
    return
  }

  if ($existingRunpath -notmatch '(^|:)/') {
    return
  }

  $patchelf = Get-Command patchelf -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $patchelf) {
    Write-Warning "patchelf is not available. Leaving host runpath in place for $Path; AppImage validation will fail until patchelf is installed."
    return
  }

  & $patchelf.Source --set-rpath $NewRunpath $Path
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to patch RUNPATH for $Path"
  }

  Write-StageLog "Patched RUNPATH for $Path -> $NewRunpath"
}

function Copy-LinuxDependencyClosure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$StageRoot,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeLibraryRoot
  )

  $queue = [System.Collections.Generic.Queue[string]]::new()
  $seen = @{}
  foreach ($seed in @(
    (Join-Path $StageRoot "app\ScreenshotTool.app\ScreenshotTool")
  )) {
    if (Test-Path $seed) {
      $queue.Enqueue($seed)
    }
  }

  foreach ($seed in Get-ChildItem -Path $RuntimeLibraryRoot -Recurse -File -ErrorAction SilentlyContinue) {
    $queue.Enqueue($seed.FullName)
  }
  foreach ($bundleBinary in Get-ChildItem -Path (Join-Path $StageRoot "runtime\System\Library\Bundles") -Recurse -File -ErrorAction SilentlyContinue) {
    $queue.Enqueue($bundleBinary.FullName)
  }

  while ($queue.Count -gt 0) {
    $target = $queue.Dequeue()
    if (-not (Test-Path $target) -or $seen.ContainsKey($target)) {
      continue
    }
    $seen[$target] = $true

    foreach ($dependency in @(Get-LinuxDependencyEntries -Path $target)) {
      if ([string]::IsNullOrWhiteSpace($dependency.Path) -or -not (Test-Path $dependency.Path)) {
        continue
      }

      $leaf = [System.IO.Path]::GetFileName($dependency.Path)
      if ($leaf -in $linuxExcludedLibraries) {
        continue
      }

      if ($dependency.Path.StartsWith($StageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }

      $destination = Join-Path $RuntimeLibraryRoot $leaf
      if (-not (Test-Path $destination)) {
        Copy-Item -Path $dependency.Path -Destination $destination -Force
        Write-StageLog "Copied Linux dependency $leaf from $($dependency.Path)"
      }
      $queue.Enqueue($destination)
    }
  }
}

function Stage-LinuxRuntime {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRootPath,
    [Parameter(Mandatory = $true)]
    [string]$StageRoot
  )

  $gnustepRoot = if (-not [string]::IsNullOrWhiteSpace($env:GNUSTEP_ROOT)) {
    [System.IO.Path]::GetFullPath($env:GNUSTEP_ROOT)
  } else {
    "/usr/GNUstep"
  }

  $runtimeBin = Ensure-Directory -Path (Join-Path $RuntimeRootPath "bin")
  $runtimeLib = Ensure-Directory -Path (Join-Path $RuntimeRootPath "lib")
  $runtimeSystem = Join-Path $RuntimeRootPath "System"
  $runtimeSystemLib = Ensure-Directory -Path (Join-Path $runtimeSystem "Library\Libraries")

  if (-not (Test-Path (Join-Path $gnustepRoot "System"))) {
    throw "GNUstep runtime root not found at $gnustepRoot. Set GNUSTEP_ROOT before staging Linux packaging payloads."
  }

  [void](Copy-DirectoryTree -Source (Join-Path $gnustepRoot "System") -Destination $runtimeSystem)
  [void](Copy-DirectoryTree -Source (Join-Path $gnustepRoot "System\Library\Libraries") -Destination $runtimeSystemLib)
  [void](Copy-DirectoryTree -Source (Join-Path $gnustepRoot "System\Library\Libraries") -Destination $runtimeLib)
  [void](Copy-DirectoryTree -Source (Join-Path $gnustepRoot "lib") -Destination $runtimeLib)
  [void](Copy-FileIfPresent -Source (Join-Path $gnustepRoot "System\Tools\defaults") -Destination (Join-Path $runtimeBin "defaults"))

  Patch-LinuxRunpathIfNeeded -Path (Join-Path $StageRoot "app\ScreenshotTool.app\ScreenshotTool") -NewRunpath '$ORIGIN:$ORIGIN/../../runtime/lib:$ORIGIN/../../runtime/System/Library/Libraries'
  Copy-LinuxDependencyClosure -StageRoot $StageRoot -RuntimeLibraryRoot $runtimeLib
}

# The MSYS2 root that holds the GNUstep toolchain: gnustep-packager's managed gnustep-cli-new root
# (GP_GNUSTEP_CLI_ROOT) when it provides one, else MSYS2 itself, whose own CLANG64 may have GNUstep.
function Resolve-MsysRoot {
  foreach ($candidate in @(
    $env:GP_GNUSTEP_CLI_ROOT,
    $env:GNUSTEP_CLI_ROOT,
    $env:MSYS2_LOCATION,
    "C:\msys64"
  )) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  throw "MSYS2 root not found. Set MSYS2_LOCATION before staging Windows packaging payloads."
}

function Get-FirstMatch {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  return $null
}

function Find-FirstDirectoryByName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root,
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $match = Get-ChildItem -Path $Root -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $Name } |
    Select-Object -First 1
  if ($null -eq $match) {
    return $null
  }
  return $match.FullName
}

function Write-WindowsGNUstepConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRootPath
  )

  $runtimeBin = Ensure-Directory -Path (Join-Path $RuntimeRootPath "bin")
  $configPath = Join-Path $runtimeBin "GNUstep.conf"
  $systemRootRelative = "../System"
  $configLines = @(
    "GNUSTEP_USER_CONFIG_FILE=",
    "GNUSTEP_SYSTEM_ROOT=$systemRootRelative",
    "GNUSTEP_LOCAL_ROOT=$systemRootRelative",
    "GNUSTEP_NETWORK_ROOT=$systemRootRelative",
    "GNUSTEP_SYSTEM_APPS=$systemRootRelative/Applications",
    "GNUSTEP_SYSTEM_ADMIN_APPS=$systemRootRelative/Applications/Admin",
    "GNUSTEP_SYSTEM_WEB_APPS=$systemRootRelative/Library/WebApplications",
    "GNUSTEP_SYSTEM_TOOLS=$systemRootRelative/Tools",
    "GNUSTEP_SYSTEM_ADMIN_TOOLS=$systemRootRelative/Tools/Admin",
    "GNUSTEP_SYSTEM_LIBRARY=$systemRootRelative/Library",
    "GNUSTEP_SYSTEM_LIBRARIES=$systemRootRelative/Library/Libraries",
    "GNUSTEP_SYSTEM_HEADERS=$systemRootRelative/Library/Headers",
    "GNUSTEP_SYSTEM_DOC=$systemRootRelative/Library/Documentation",
    "GNUSTEP_SYSTEM_DOC_MAN=$systemRootRelative/Library/Documentation/man",
    "GNUSTEP_SYSTEM_DOC_INFO=$systemRootRelative/Library/Documentation/info",
    "GNUSTEP_NETWORK_APPS=$systemRootRelative/Applications",
    "GNUSTEP_NETWORK_ADMIN_APPS=$systemRootRelative/Applications/Admin",
    "GNUSTEP_NETWORK_WEB_APPS=$systemRootRelative/Library/WebApplications",
    "GNUSTEP_NETWORK_TOOLS=$systemRootRelative/Tools",
    "GNUSTEP_NETWORK_ADMIN_TOOLS=$systemRootRelative/Tools/Admin",
    "GNUSTEP_NETWORK_LIBRARY=$systemRootRelative/Library",
    "GNUSTEP_NETWORK_LIBRARIES=$systemRootRelative/Library/Libraries",
    "GNUSTEP_NETWORK_HEADERS=$systemRootRelative/Library/Headers",
    "GNUSTEP_NETWORK_DOC=$systemRootRelative/Library/Documentation",
    "GNUSTEP_NETWORK_DOC_MAN=$systemRootRelative/Library/Documentation/man",
    "GNUSTEP_NETWORK_DOC_INFO=$systemRootRelative/Library/Documentation/info",
    "GNUSTEP_LOCAL_APPS=$systemRootRelative/Applications",
    "GNUSTEP_LOCAL_ADMIN_APPS=$systemRootRelative/Applications/Admin",
    "GNUSTEP_LOCAL_WEB_APPS=$systemRootRelative/Library/WebApplications",
    "GNUSTEP_LOCAL_TOOLS=$systemRootRelative/Tools",
    "GNUSTEP_LOCAL_ADMIN_TOOLS=$systemRootRelative/Tools/Admin",
    "GNUSTEP_LOCAL_LIBRARY=$systemRootRelative/Library",
    "GNUSTEP_LOCAL_LIBRARIES=$systemRootRelative/Library/Libraries",
    "GNUSTEP_LOCAL_HEADERS=$systemRootRelative/Library/Headers",
    "GNUSTEP_LOCAL_DOC=$systemRootRelative/Library/Documentation",
    "GNUSTEP_LOCAL_DOC_MAN=$systemRootRelative/Library/Documentation/man",
    "GNUSTEP_LOCAL_DOC_INFO=$systemRootRelative/Library/Documentation/info",
    "GNUSTEP_MAKEFILES=$systemRootRelative/Library/Makefiles"
  )

  Set-Content -Path $configPath -Value $configLines -Encoding ascii
  Write-StageLog "Wrote Windows GNUstep runtime config to $configPath"
}

function Stage-WindowsRuntime {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRootPath
  )

  $msysRoot = Resolve-MsysRoot
  $clang64Root = Get-FirstMatch -Candidates @(
    (Join-Path $msysRoot "clang64"),
    "C:\clang64"
  )
  if ($null -eq $clang64Root) {
    throw "MSYS2 CLANG64 root not found."
  }

  $runtimeBin = Ensure-Directory -Path (Join-Path $RuntimeRootPath "bin")
  $runtimeEtcFonts = Ensure-Directory -Path (Join-Path $RuntimeRootPath "etc\fonts")
  $runtimeSystemLib = Ensure-Directory -Path (Join-Path $RuntimeRootPath "System\Library\Libraries")
  $runtimeSystemBundles = Ensure-Directory -Path (Join-Path $RuntimeRootPath "System\Library\Bundles")
  $runtimeSystemThemes = Ensure-Directory -Path (Join-Path $RuntimeRootPath "System\Library\Themes")
  $runtimeSystemMakefiles = Ensure-Directory -Path (Join-Path $RuntimeRootPath "System\Library\Makefiles")

  foreach ($fontsDir in @(
    (Join-Path $clang64Root "etc\fonts")
  )) {
    [void](Copy-DirectoryTree -Source $fontsDir -Destination $runtimeEtcFonts)
  }

  $defaultsSource = Get-FirstMatch -Candidates @(
    (Join-Path $clang64Root "bin\defaults.exe"),
    (Join-Path $msysRoot "clang64\bin\defaults.exe")
  )
  if ($null -ne $defaultsSource) {
    [void](Copy-FileIfPresent -Source $defaultsSource -Destination (Join-Path $runtimeBin "defaults.exe"))
  }

  foreach ($libraryDir in @(
    (Join-Path $clang64Root "bin"),
    (Join-Path $clang64Root "lib"),
    (Join-Path $clang64Root "lib\GNUstep\Libraries"),
    (Find-FirstDirectoryByName -Root $clang64Root -Name "Libraries")
  )) {
    if (-not [string]::IsNullOrWhiteSpace($libraryDir) -and (Test-Path $libraryDir)) {
      [void](Copy-MatchingFiles -SourceDirectory $libraryDir -Patterns @("*.dll") -DestinationDirectory $runtimeSystemLib)
    }
  }
  [void](Copy-MatchingFiles -SourceDirectory $runtimeSystemLib -Patterns @("*.dll") -DestinationDirectory $runtimeBin)

  foreach ($bundleDir in @(
    (Join-Path $clang64Root "lib\GNUstep\Bundles"),
    (Find-FirstDirectoryByName -Root $clang64Root -Name "Bundles")
  )) {
    if (-not [string]::IsNullOrWhiteSpace($bundleDir)) {
      [void](Copy-DirectoryTree -Source $bundleDir -Destination $runtimeSystemBundles)
      break
    }
  }

  foreach ($themeDir in @(
    (Join-Path $clang64Root "share\GNUstep\Themes"),
    (Find-FirstDirectoryByName -Root $clang64Root -Name "Themes")
  )) {
    if (-not [string]::IsNullOrWhiteSpace($themeDir)) {
      [void](Copy-DirectoryTree -Source $themeDir -Destination $runtimeSystemThemes)
      break
    }
  }

  foreach ($makefilesDir in @(
    (Join-Path $clang64Root "share\GNUstep\Makefiles"),
    (Find-FirstDirectoryByName -Root $clang64Root -Name "Makefiles")
  )) {
    if (-not [string]::IsNullOrWhiteSpace($makefilesDir)) {
      [void](Copy-DirectoryTree -Source $makefilesDir -Destination $runtimeSystemMakefiles)
      break
    }
  }

  Write-WindowsGNUstepConfig -RuntimeRootPath $RuntimeRootPath
}

function Write-LicenseFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,
    [Parameter(Mandatory = $true)]
    [string]$Version
  )

  Ensure-Directory -Path $DestinationRoot | Out-Null

  [void](Copy-FileIfPresent -Source (Join-Path $RepoRoot "COPYING") -Destination (Join-Path $DestinationRoot "ScreenshotTool.txt"))

  $runtimeNotice = @(
    "ScreenshotTool packaging runtime notice"
    "Version: $Version"
    ""
    "Bundled runtime components:"
  )

  if ($IsLinux) {
    $runtimeNotice += @(
      "- GNUstep base/gui/back runtime from /usr/GNUstep"
      "- GNUstep themes and bundles copied into runtime/System"
      "- Linux shared-library closure staged under runtime/lib"
      ""
      "Primary runtime license family: LGPL-2.1-or-later for GNUstep runtime components."
    )
  } elseif ($IsWindows) {
    $runtimeNotice += @(
      "- GNUstep runtime assets staged from MSYS2 CLANG64"
      "- GNUstep bundles/themes copied into runtime/System"
      ""
      "Primary runtime license family: LGPL-2.1-or-later for GNUstep runtime components."
    )
  }

  Set-Content -Path (Join-Path $DestinationRoot "gnustep-runtime.txt") -Value $runtimeNotice -Encoding utf8
}

$manifest = Get-ManifestData -Path $manifestFullPath
$version = Get-ReleaseVersion -Manifest $manifest -RequestedVersion $PackageVersion

if (-not (Test-Path $appSourceRoot)) {
  throw "Built app bundle missing at $appSourceRoot. Run scripts/build_release.ps1 first."
}

Reset-Directory -Path $resolvedStageRoot
Ensure-Directory -Path $metadataIconRoot | Out-Null
Ensure-Directory -Path $metadataLicenseRoot | Out-Null
Ensure-Directory -Path (Join-Path $runtimeRoot "bin") | Out-Null

if (-not (Copy-DirectoryTree -Source $appSourceRoot -Destination $appStageRoot)) {
  throw "Failed to copy app bundle from $appSourceRoot"
}

$normalizedEntryPath = Normalize-StagedAppEntry -BundleRoot $appStageRoot
Stage-UpdaterHelper -RepoRoot $repoRoot -BundleRoot $appStageRoot
Update-StagedBundleVersion -BundleRoot $appStageRoot -Version $version
Write-StageLog "Staged app bundle entry: $normalizedEntryPath"

[void](Copy-FileIfPresent -Source (Join-Path $repoRoot "Resources\ScreenshotToolIcon.png") -Destination (Join-Path $metadataIconRoot "ScreenshotToolIcon.png"))
Write-LicenseFiles -RepoRoot $repoRoot -DestinationRoot $metadataLicenseRoot -Version $version

if ($IsLinux) {
  Stage-LinuxRuntime -RepoRoot $repoRoot -RuntimeRootPath $runtimeRoot -StageRoot $resolvedStageRoot
} elseif ($IsWindows) {
  Stage-WindowsRuntime -RepoRoot $repoRoot -RuntimeRootPath $runtimeRoot
} else {
  throw "Packaging stage is only implemented for Linux and Windows hosts."
}

Write-StageLog "Stage output created at $resolvedStageRoot"
Write-Host "Stage output created at $resolvedStageRoot"
