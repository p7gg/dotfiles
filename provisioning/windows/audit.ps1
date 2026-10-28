#Requires -Version 5.1
<#
.SYNOPSIS
Read-only audit of the Windows host contract for the Arch/WSL workflow.

.DESCRIPTION
Checks the Windows build, WSL, WinGet packages, .wslconfig, Windows Terminal
settings, and the SSH agent relay. It never installs, removes, or changes
anything. Run it from Windows with pwsh, or from WSL with:

    just windows-audit

.PARAMETER Strict
Treat warnings as failures.

.PARAMETER NoColor
Disable colored output.

.PARAMETER NoUpdateCheck
Skip the GitHub API check for the latest stable WSL release.

.NOTES
The PowerShell scripts are the source of truth. provisioning/windows/run.sh is
only a WSL convenience wrapper; the same script must also run natively.
#>
[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$NoColor,
    [switch]$NoUpdateCheck
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'lib\common.ps1')
Initialize-Output -NoColor:$NoColor

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # Encoding is best-effort; the audit still works with the console default.
}

function Test-WingetPackage {
    param(
        [string]$WingetPath,
        [string]$Id,
        [string]$Kind
    )

    $result = Get-InstalledWingetPackage -WingetPath $WingetPath -Id $Id

    if ($result.Installed) {
        if ($result.Version) {
            Write-Result -Status ok -Message "$Kind package $Id ($($result.Version))"
        } else {
            Write-Result -Status ok -Message "$Kind package $Id"
        }
        return
    }

    if ($result.Missing) {
        if ($Kind -eq 'required') {
            Write-Result -Status fail -Message "required package missing: $Id"
        } else {
            Write-Result -Status warn -Message "optional package missing: $Id"
        }
        return
    }

    $detail = ($result.Output -replace '\s+', ' ')
    Write-Result -Status warn -Message "could not query $Id (winget exit $($result.ExitCode)): $detail"
}

# --- Windows -----------------------------------------------------------------

Write-Section 'Windows host'

$windows = Get-WindowsInfo
if ($windows.Build -ge 22000) {
    Write-Result -Status ok -Message "$($windows.Caption) $($windows.Version) (build $($windows.Build), $($windows.Architecture))"
} else {
    Write-Result -Status warn -Message "$($windows.Caption) build $($windows.Build) is older than Windows 11; the documented WSL setup targets Windows 11"
}

if ($windows.Architecture -match 'ARM') {
    Write-Result -Status warn -Message 'ARM64 Windows: the Arch WSL image in the docs is x86_64; use an ARM-compatible image'
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
Write-Info "Running as $(if ($isAdmin) { 'administrator' } else { 'standard user' }); the audit is read-only"

# --- Reboot state ------------------------------------------------------------

Write-Section 'Reboot state'

if (Test-PendingReboot) {
    Write-Result -Status warn -Message 'a reboot is pending; finish it before provisioning'
} else {
    Write-Result -Status ok -Message 'no pending reboot detected'
}

# --- WinGet ------------------------------------------------------------------

Write-Section 'WinGet'

$wingetPath = Get-WingetPath
if (-not $wingetPath) {
    Write-Result -Status fail -Message 'winget.exe not found; install App Installer from the Microsoft Store'
} else {
    $wingetVersion = (& $wingetPath --version 2>&1 | Select-Object -First 1)
    Write-Result -Status ok -Message "winget $wingetVersion ($wingetPath)"
}

$required = @(Read-PackageList -Path (Join-Path $PSScriptRoot 'packages\required.txt'))
$optionalCategories = @(Get-OptionalCategories)
$optional = @()
if ($optionalCategories.Count -eq 0) {
    Write-Result -Status warn -Message 'no optional package categories found'
} else {
    $optional = @(Get-OptionalPackages -Categories $optionalCategories | ForEach-Object { $_.Id })
}

if ($required.Count -eq 0) {
    Write-Result -Status fail -Message 'the required Windows package list is empty'
}

$duplicates = @($required + $optional | Group-Object | Where-Object { $_.Count -gt 1 })
foreach ($duplicate in $duplicates) {
    Write-Result -Status fail -Message "package listed more than once: $($duplicate.Name)"
}

Write-Info "Tracking $($required.Count) required and $($optional.Count) optional package IDs across $($optionalCategories.Count) categories"

if ($wingetPath) {
    foreach ($id in $required) {
        Test-WingetPackage -WingetPath $wingetPath -Id $id -Kind required
    }
    foreach ($id in $optional) {
        Test-WingetPackage -WingetPath $wingetPath -Id $id -Kind optional
    }
}

# --- WSL ---------------------------------------------------------------------

Write-Section 'WSL'

$wsl = Get-WslVersion
if (-not $wsl.Present) {
    Write-Result -Status fail -Message 'wsl.exe not found; install WSL before importing Arch'
} else {
    if (-not $wsl.Usable) {
        Write-Result -Status fail -Message "wsl.exe is present but not usable (exit $($wsl.ExitCode)); install or repair WSL"
    } elseif ($wsl.Version) {
        Write-Result -Status ok -Message "WSL $($wsl.Version)"

        $parsed = $null
        if ([version]::TryParse($wsl.Version, [ref]$parsed) -and $parsed.Major -lt 2) {
            Write-Result -Status warn -Message "WSL $($wsl.Version) is older than 2.0; run 'wsl --update' for systemd support"
        }

        if (-not $NoUpdateCheck) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                $release = Invoke-RestMethod `
                    -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest' `
                    -Headers @{ 'User-Agent' = 'dotfiles-windows-audit' } `
                    -TimeoutSec 10
                $latest = $release.tag_name
                if (-not $latest) {
                    throw 'the release response has no tag_name'
                }
                if ([version](Format-Version4 $latest) -gt [version](Format-Version4 $wsl.Version)) {
                    Write-Result -Status warn -Message "WSL $($wsl.Version) is behind the latest stable release $latest; run 'wsl --update'"
                } else {
                    Write-Result -Status ok -Message "WSL $($wsl.Version) is current with the latest stable release"
                }
            } catch {
                Write-Info "Could not check the latest WSL release: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Result -Status warn -Message "could not parse 'wsl --version' output"
    }

    if ($wsl.Usable) {
        $listOutput = (& wsl.exe --list --verbose 2>&1) -replace "`0", ''
        $defaultLine = $listOutput | Where-Object { $_ -match '^\s*\*\s+' } | Select-Object -First 1
        if ($defaultLine -and $defaultLine -match '^\s*\*\s+(\S+)\s+(\S+)\s+(\d+)') {
            $distro = $Matches[1]
            $state = $Matches[2]
            $distroVersion = [int]$Matches[3]
            $stateText = if ($state -match 'Running') { 'running' } else { 'stopped' }
            Write-Result -Status ok -Message "default distro: $distro (WSL $distroVersion, $stateText)"
            if ($distroVersion -ne 2) {
                Write-Result -Status warn -Message "$distro is WSL $distroVersion; the Arch setup expects WSL 2"
            }
        } else {
            Write-Result -Status warn -Message 'no default WSL distro found; import Arch before running the Linux bootstrap'
        }
    }
}

# --- .wslconfig --------------------------------------------------------------

Write-Section '.wslconfig'

$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
if (-not (Test-Path -LiteralPath $wslConfigPath)) {
    Write-Info 'No .wslconfig; WSL defaults are in use'
} else {
    $ini = Read-IniFile -Path $wslConfigPath
    Write-Result -Status ok -Message ".wslconfig found: $wslConfigPath"

    if ($ini.ContainsKey('wsl2')) {
        $wsl2 = $ini['wsl2']
        $keys = @('memory', 'swap', 'processors', 'localhostForwarding', 'nestedVirtualization', 'guiApplications')
        $found = $false
        foreach ($key in $keys) {
            if ($wsl2.ContainsKey($key)) {
                $found = $true
                $value = Format-WslValue -Value $wsl2[$key]
                Write-Info "wsl2.$key = $value"
            }
        }
        if (-not $found) {
            Write-Info 'The [wsl2] section has no tracked keys; WSL defaults are in use'
        }
    } else {
        Write-Info 'No [wsl2] section; WSL defaults are in use'
    }
}

# --- Windows Terminal --------------------------------------------------------

Write-Section 'Windows Terminal'

$terminalCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$terminalPath = $terminalCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $terminalPath) {
    Write-Result -Status warn -Message 'Windows Terminal settings not found; launch Terminal once'
} else {
    Write-Result -Status ok -Message "settings: $terminalPath"

    $settings = $null
    try {
        $settings = Get-Content -LiteralPath $terminalPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Result -Status warn -Message "could not parse Terminal settings (JSONC comments require PowerShell 7): $($_.Exception.Message)"
    }

    if ($settings) {
        $defaultProfile = $settings.defaultProfile
        $profile = $null
        if ($defaultProfile -and $settings.profiles -and $settings.profiles.list) {
            $profile = $settings.profiles.list | Where-Object { $_.guid -eq $defaultProfile } | Select-Object -First 1
        }

        if ($profile) {
            Write-Result -Status ok -Message "default profile: $($profile.name)"
        } elseif ($defaultProfile) {
            Write-Result -Status warn -Message "default profile GUID $defaultProfile is not in profiles.list"
        } else {
            Write-Result -Status warn -Message 'defaultProfile is not set'
        }

        $fontFace = $null
        if ($settings.profiles -and $settings.profiles.defaults -and $settings.profiles.defaults.font) {
            $fontFace = $settings.profiles.defaults.font.face
        }

        if ($fontFace) {
            Write-Result -Status ok -Message "default font: $fontFace"
            if (-not (Test-FontInstalled -Face $fontFace)) {
                Write-Result -Status warn -Message "font '$fontFace' is not registered for the current user or machine"
            }
        } else {
            Write-Result -Status warn -Message 'profiles.defaults.font.face is unset; Terminal uses its default font'
        }

        $scheme = $null
        if ($settings.profiles -and $settings.profiles.defaults -and $settings.profiles.defaults.colorScheme) {
            $scheme = $settings.profiles.defaults.colorScheme
        }
        if ($scheme -is [string]) {
            Write-Info "color scheme: $scheme"
        } elseif ($scheme -and $scheme.dark) {
            Write-Info "dark color scheme: $($scheme.dark)"
        }
    }
}

# --- SSH agent relay ---------------------------------------------------------

Write-Section 'SSH agent relay'

$service = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Result -Status warn -Message 'ssh-agent service not found; install the OpenSSH client if you need it'
} elseif ($service.StartType -eq 'Disabled') {
    Write-Result -Status ok -Message 'ssh-agent service is Disabled (Bitwarden can own the pipe)'
} else {
    Write-Result -Status warn -Message "ssh-agent service is $($service.StartType); disable it so Bitwarden can own the pipe"
}

$agentPipe = '\\.\pipe\openssh-ssh-agent'
if (Test-Path -LiteralPath $agentPipe) {
    Write-Result -Status ok -Message "SSH agent pipe is reachable: $agentPipe"
} else {
    Write-Result -Status warn -Message 'SSH agent pipe is not reachable; start Bitwarden and enable its SSH agent'
}

$npiperelay = Get-Command npiperelay.exe -ErrorAction SilentlyContinue
$npiperelayPath = if ($npiperelay) {
    $npiperelay.Source
} else {
    $packageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $candidates = @(
        Get-ChildItem -Path $packageRoot -Filter 'albertony.npiperelay_*' -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'npiperelay.exe' } |
            Where-Object { Test-Path -LiteralPath $_ }
    )
    if ($candidates.Count -gt 0) { $candidates[0] } else { $null }
}

if ($npiperelayPath) {
    Write-Result -Status ok -Message "npiperelay: $npiperelayPath"
} else {
    Write-Result -Status warn -Message 'npiperelay.exe not found; install albertony.npiperelay'
}

# --- Summary -----------------------------------------------------------------

Write-Section 'Summary'

$exitCode = Show-Summary -Strict:$Strict
exit $exitCode
