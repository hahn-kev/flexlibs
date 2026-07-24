#Requires -Version 5.1
<#
.SYNOPSIS
  Download and silently install FieldWorks for CI, or restore registry after a cache hit.

.DESCRIPTION
  Uses the offline x64 installer from downloads.languagetechnology.org.
  On cache restore of the install directories, skip download/install and only
  ensure HKLM registry keys exist so discovery (and FwRegistryHelper) work.
#>
[CmdletBinding()]
param(
    [string]$Version = "9.3.9.1",
    [string]$Build = "1439",
    [string]$InstallerUrl = "",
    [string]$CodeDir = "C:\Program Files\SIL\FieldWorks 9",
    [string]$ProjectsDir = "C:\ProgramData\SIL\FieldWorks\Projects",
    [string]$DownloadDir = "C:\fw-ci\installer",
    [string]$InstallLog = "C:\fw-ci\fw-install.log"
)

$ErrorActionPreference = "Stop"

function Ensure-Registry {
    param([string]$CodeDir, [string]$ProjectsDir)

    $regPath = "HKLM:\SOFTWARE\SIL\FieldWorks\9"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    New-ItemProperty -Path $regPath -Name "RootCodeDir" -Value $CodeDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "ProjectsDir" -Value $ProjectsDir -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "Data_Directory" -Value (Split-Path $ProjectsDir -Parent) -PropertyType String -Force | Out-Null
    Write-Host "Registry ready: RootCodeDir=$CodeDir ProjectsDir=$ProjectsDir"
}

function Test-FieldWorksInstalled {
    param([string]$CodeDir)
    return (Test-Path (Join-Path $CodeDir "FieldWorks.exe")) -and (Test-Path (Join-Path $CodeDir "FwUtils.dll"))
}

if (-not $InstallerUrl) {
    # Path pattern from https://software.sil.org/fieldworks/download/fw-93/fw-939/
    $InstallerUrl = "https://downloads.languagetechnology.org/fieldworks/9.3.9/$Build/FieldWorks_${Version}_Offline_x64.exe"
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $InstallLog) | Out-Null
New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null

if (Test-FieldWorksInstalled -CodeDir $CodeDir) {
    Write-Host "FieldWorks already present at $CodeDir (cache hit or prior install)"
    Ensure-Registry -CodeDir $CodeDir -ProjectsDir $ProjectsDir
    exit 0
}

$installerName = Split-Path $InstallerUrl -Leaf
$installerPath = Join-Path $DownloadDir $installerName

if (-not (Test-Path $installerPath)) {
    Write-Host "Downloading FieldWorks installer..."
    Write-Host "  URL: $InstallerUrl"
    Write-Host "  To:  $installerPath"
    # Use BITS-friendly curl for large files with resume
    & curl.exe -L --retry 3 --retry-delay 5 -o $installerPath $InstallerUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Host "Using cached installer: $installerPath"
}

$sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
Write-Host "Installer size: ${sizeMB} MB"
Write-Host "Silent installing FieldWorks (/quiet /norestart)..."
Write-Host "Log: $InstallLog"

$proc = Start-Process -FilePath $installerPath `
    -ArgumentList @("/quiet", "/norestart", "/log", $InstallLog) `
    -Wait -PassThru -NoNewWindow

Write-Host "Installer exit code: $($proc.ExitCode)"
# Burn/WiX often returns 0 (success), 3010 (reboot required), or 1641 (restart initiated)
if ($proc.ExitCode -notin @(0, 3010, 1641)) {
    if (Test-Path $InstallLog) {
        Write-Host "---- last 80 lines of install log ----"
        Get-Content $InstallLog -Tail 80
    }
    throw "FieldWorks installer failed with exit code $($proc.ExitCode)"
}

if (-not (Test-FieldWorksInstalled -CodeDir $CodeDir)) {
    if (Test-Path $InstallLog) {
        Write-Host "---- last 80 lines of install log ----"
        Get-Content $InstallLog -Tail 80
    }
    throw "FieldWorks.exe not found after install at $CodeDir"
}

Ensure-Registry -CodeDir $CodeDir -ProjectsDir $ProjectsDir
Write-Host "FieldWorks install complete."
