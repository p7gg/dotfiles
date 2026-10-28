#Requires -Version 5.1
<#
.SYNOPSIS
Install missing Windows packages for the Arch/WSL workflow.

.DESCRIPTION
Installs the tracked required packages and, optionally, selected optional
categories with WinGet. It never uninstalls or upgrades anything. Run it as
your normal user; WinGet requests UAC for installers that need elevation.

Run it from Windows with pwsh, or from WSL with:

    just windows-check
    just windows-dry-run
    just windows-bootstrap

.PARAMETER Check
Validate prerequisites and package lists, then exit without querying or
installing packages.

.PARAMETER DryRun
Query installed packages and print the WinGet commands without executing them.

.PARAMETER Yes
Do not prompt before installing. Required for unattended runs.

.PARAMETER Force
Continue when a reboot is pending. The bootstrap still reports the pending
reboot after installing.

.PARAMETER NoSilent
Do not pass --silent to WinGet. Use this when an installer needs its UI.

.PARAMETER NoColor
Disable colored output.

.PARAMETER Optional
Optional categories to install: apps, games, hardware, or all.

.NOTES
The PowerShell scripts are the source of truth. provisioning/windows/run.sh is
only a WSL convenience wrapper; the same script must also run natively.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Force,
    [switch]$NoSilent,
    [switch]$NoColor,
    [string[]]$Optional = @()
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'lib\common.ps1')
Initialize-Output -NoColor:$NoColor

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # Encoding is best-effort; the bootstrap still works with the console default.
}

# Accept both `-Optional apps,games` and `-Optional apps -Optional games`.
$Optional = @(
    $Optional |
        ForEach-Object { $_ -split ',' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)

if ($Check -and $DryRun) {
    Write-Result -Status fail -Message 'use either -Check or -DryRun, not both'
    $exitCode = Show-Summary
    exit $exitCode
}

# --- Preflight ---------------------------------------------------------------

Write-Section 'Preflight'

$windows = Get-WindowsInfo
if ($windows.Build -ge 22000) {
    Write-Result -Status ok -Message "$($windows.Caption) $($windows.Version) (build $($windows.Build), $($windows.Architecture))"
} else {
    Write-Result -Status fail -Message "$($windows.Caption) build $($windows.Build) is older than Windows 11"
}

if ($windows.Architecture -match 'ARM') {
    Write-Result -Status warn -Message 'ARM64 Windows: the Arch WSL image in the docs is x86_64; use an ARM-compatible image'
}

$wingetPath = Get-WingetPath
if (-not $wingetPath) {
    Write-Result -Status fail -Message 'winget.exe not found; install App Installer from the Microsoft Store'
} else {
    $wingetVersion = (& $wingetPath --version 2>&1 | Select-Object -First 1)
    Write-Result -Status ok -Message "winget $wingetVersion ($wingetPath)"
}

$wsl = Get-WslVersion
if (-not $wsl.Present) {
    Write-Result -Status fail -Message 'wsl.exe not found; install WSL before provisioning Windows packages'
} elseif (-not $wsl.Usable) {
    Write-Result -Status fail -Message "wsl.exe is present but not usable (exit $($wsl.ExitCode)); install or repair WSL"
} else {
    Write-Result -Status ok -Message "WSL $($wsl.Version)"
}

if (Test-PendingReboot) {
    if ($Force) {
        Write-Result -Status warn -Message 'a reboot is pending; continuing because -Force was passed'
    } else {
        Write-Result -Status fail -Message 'a reboot is pending; reboot first or rerun with -Force'
    }
} else {
    Write-Result -Status ok -Message 'no pending reboot detected'
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
Write-Info "Running as $(if ($isAdmin) { 'administrator' } else { 'standard user' }); WinGet requests UAC for machine-scope installers"

$required = @(Read-PackageList -Path (Join-Path $PSScriptRoot 'packages\required.txt'))
if ($required.Count -eq 0) {
    Write-Result -Status fail -Message 'the required Windows package list is empty'
}

$optionalPackages = @()
if ($Optional.Count -gt 0) {
    try {
        $optionalPackages = @(Get-OptionalPackages -Categories $Optional)
    } catch {
        Write-Result -Status fail -Message $_.Exception.Message
    }
}

$allIds = @($required + @($optionalPackages | ForEach-Object { $_.Id }))
$duplicates = @($allIds | Group-Object | Where-Object { $_.Count -gt 1 })
foreach ($duplicate in $duplicates) {
    Write-Result -Status fail -Message "package listed more than once: $($duplicate.Name)"
}

Write-Info "Selected $($required.Count) required and $($optionalPackages.Count) optional package(s)"

if ($script:Failures -gt 0) {
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

if ($Check) {
    Write-Info 'Check complete: prerequisites and package lists are valid.'
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

# --- Package status ----------------------------------------------------------

Write-Section 'Package status'

$requiredPackages = @($required | ForEach-Object {
        [pscustomobject]@{
            Id       = $_
            Category = 'required'
        }
    })
$selectedPackages = @($requiredPackages + $optionalPackages)
$installList = @()

foreach ($package in $selectedPackages) {
    $status = Get-InstalledWingetPackage -WingetPath $wingetPath -Id $package.Id

    if ($status.Installed) {
        $matchedBy = if ($status.MatchedBy -eq 'alias') { " (matched '$($status.Alias)')" } else { '' }
        if ($status.Version) {
            Write-Result -Status ok -Message "$($package.Id) is installed$matchedBy ($($status.Version))"
        } else {
            Write-Result -Status ok -Message "$($package.Id) is installed$matchedBy"
        }
        continue
    }

    if ($status.Missing) {
        Write-Info "missing: $($package.Id) [$($package.Category)]"
        $installList += $package
        continue
    }

    Write-Result -Status warn -Message "could not query $($package.Id) (winget exit $($status.ExitCode)); will attempt install"
    $installList += $package
}

Write-Info "$($selectedPackages.Count - $installList.Count) installed, $($installList.Count) to install"

if ($installList.Count -eq 0) {
    Write-Result -Status ok -Message 'no missing packages'
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

# --- Dry run -----------------------------------------------------------------

if ($DryRun) {
    Write-Section 'Dry run'

    foreach ($package in $installList) {
        $arguments = Get-WingetInstallArgs -Id $package.Id -NoSilent:$NoSilent
        Write-Info "$($package.Id) [$($package.Category)]"
        Write-Info "  $wingetPath $($arguments -join ' ')"
    }

    Write-Info 'Dry run complete; no packages were installed.'
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

# --- Install -----------------------------------------------------------------

if (-not $Yes) {
    if ([Console]::IsInputRedirected) {
        Write-Result -Status fail -Message 'refusing to install without -Yes when stdin is not a terminal'
        Write-Section 'Summary'
        $exitCode = Show-Summary
        exit $exitCode
    }

    $answer = Read-Host "Install $($installList.Count) package(s)? [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Info 'Aborted.'
        exit 1
    }
}

Write-Section 'Installing'

$failedPackages = @()
foreach ($package in $installList) {
    Write-Section "Installing $($package.Id) [$($package.Category)]"
    $installExit = Install-WingetPackage -WingetPath $wingetPath -Id $package.Id -NoSilent:$NoSilent

    if ($installExit -eq 0) {
        Write-Result -Status ok -Message "installed $($package.Id)"
        continue
    }

    $recheck = Get-InstalledWingetPackage -WingetPath $wingetPath -Id $package.Id
    if ($recheck.Installed) {
        Write-Result -Status ok -Message "$($package.Id) is installed after all"
        continue
    }

    Write-Result -Status fail -Message "winget install failed for $($package.Id) (exit $installExit); retry with -NoSilent if the installer needs UI"
    $failedPackages += $package.Id
}

# --- Post-install ------------------------------------------------------------

Write-Section 'Post-install'

if (Test-PendingReboot) {
    Write-Result -Status warn -Message 'a reboot is required to finish the installation'
} else {
    Write-Result -Status ok -Message 'no pending reboot detected'
}

if ($failedPackages.Count -gt 0) {
    Write-Info "Failed packages: $($failedPackages -join ', ')"
}

Write-Section 'Audit'

& (Join-Path $PSScriptRoot 'audit.ps1') -NoUpdateCheck -NoColor:$NoColor
if ($LASTEXITCODE -ne 0) {
    Write-Result -Status fail -Message 'the post-install audit reported failures'
}

Write-Section 'Summary'
$exitCode = Show-Summary
exit $exitCode
