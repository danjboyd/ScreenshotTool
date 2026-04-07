[CmdletBinding()]
param(
  [string]$ManifestPath = "packaging/package.manifest.json",
  [string]$PackageVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$manifestFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))

if (-not [string]::IsNullOrWhiteSpace($PackageVersion)) {
  $env:GP_PACKAGE_VERSION_OVERRIDE = $PackageVersion
}

function Invoke-LoggedCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $([string]::Join(' ', $ArgumentList))"
  }
}

function ConvertTo-MsysPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath
  )

  $normalized = [System.IO.Path]::GetFullPath($WindowsPath).Replace("\", "/")
  if ($normalized -match "^([A-Za-z]):/(.*)$") {
    return "/$($Matches[1].ToLowerInvariant())/$($Matches[2])"
  }
  return $normalized
}

function Resolve-MsysRoot {
  foreach ($candidate in @(
    $env:MSYS2_LOCATION,
    "C:\msys64"
  )) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  throw "MSYS2 root not found. Set MSYS2_LOCATION before running the Windows packaging build."
}

function Resolve-WindowsGNUstepSh {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Clang64Root
  )

  foreach ($candidate in @(
    (Join-Path $Clang64Root "share\GNUstep\Makefiles\GNUstep.sh"),
    (Join-Path $Clang64Root "System\Library\Makefiles\GNUstep.sh")
  )) {
    if (Test-Path $candidate) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }

  $match = Get-ChildItem -Path $Clang64Root -Recurse -Filter GNUstep.sh -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -ne $match) {
    return $match.FullName
  }

  throw "Unable to locate GNUstep.sh under $Clang64Root."
}

function Invoke-BashBuild {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BashExe,
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$GNUstepSh
  )

  $repoPosix = ConvertTo-MsysPath -WindowsPath $RepoRoot
  $gnustepPosix = ConvertTo-MsysPath -WindowsPath $GNUstepSh
  $command = "set -eo pipefail; export ZSH_VERSION=`"${ZSH_VERSION:-}`"; cd '$repoPosix'; set +u; source '$gnustepPosix'; set -u; make -j`$(nproc)"
  Invoke-LoggedCommand -FilePath $BashExe -ArgumentList @("-lc", $command)
}

if (-not (Test-Path $manifestFullPath)) {
  throw "Manifest not found: $manifestFullPath"
}

if (-not (Test-Path (Join-Path $repoRoot "third_party\libs-OpenSave\Source\GNUmakefile"))) {
  throw "libs-OpenSave submodule is missing. Run: git submodule update --init --recursive"
}

$gitMetadataPath = Join-Path $repoRoot ".git"
if (Test-Path $gitMetadataPath) {
  Invoke-LoggedCommand -FilePath "git" -ArgumentList @("-C", $repoRoot, "submodule", "update", "--init", "--recursive")
}

if ($IsLinux) {
  $bashExe = Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $bashExe) {
    throw "bash is required for the Linux packaging build."
  }

  $gnustepSh = if (-not [string]::IsNullOrWhiteSpace($env:GNUSTEP_SH)) {
    [System.IO.Path]::GetFullPath($env:GNUSTEP_SH)
  } else {
    "/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"
  }
  if (-not (Test-Path $gnustepSh)) {
    throw "GNUstep.sh not found at $gnustepSh. Set GNUSTEP_SH before running the Linux packaging build."
  }

  Invoke-BashBuild -BashExe $bashExe.Source -RepoRoot $repoRoot -GNUstepSh $gnustepSh
  exit 0
}

if ($IsWindows) {
  $msysRoot = Resolve-MsysRoot
  $bashExe = Join-Path $msysRoot "usr\bin\bash.exe"
  if (-not (Test-Path $bashExe)) {
    throw "MSYS2 bash not found at $bashExe."
  }

  $clang64Root = Join-Path $msysRoot "clang64"
  if (-not (Test-Path $clang64Root)) {
    throw "MSYS2 CLANG64 root not found at $clang64Root."
  }

  $env:MSYSTEM = "CLANG64"
  $gnustepSh = Resolve-WindowsGNUstepSh -Clang64Root $clang64Root
  Invoke-BashBuild -BashExe $bashExe -RepoRoot $repoRoot -GNUstepSh $gnustepSh
  exit 0
}

throw "Packaging builds are only implemented for Linux and Windows hosts."
