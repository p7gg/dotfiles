#Requires -Version 7.0
<#
.SYNOPSIS
Apply managed Windows host settings for the Arch/WSL workflow.

.DESCRIPTION
Merges the tracked .wslconfig keys and Windows Terminal defaults into the
current user's files. Existing files are backed up first; unrelated settings
are preserved. The audit remains read-only.

Run it from Windows with pwsh, or from WSL with:

    just windows-settings-check
    just windows-settings-dry-run
    just windows-settings

.PARAMETER Check
Report whether the tracked settings differ without changing anything.

.PARAMETER DryRun
Print the planned changes without changing anything.

.PARAMETER Yes
Do not prompt before applying. Required for unattended runs.

.PARAMETER NoColor
Disable colored output.

.NOTES
Windows Terminal hot-reloads settings.json, so no restart is required. The
script rewrites the JSON without comments; the timestamped backup keeps the
previous file.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoColor
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'lib\common.ps1')
Initialize-Output -NoColor:$NoColor

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # Encoding is best-effort; the settings apply still works with the default.
}

function Backup-ManagedFile {
    param(
        [string]$Path,
        [int]$Retention = 3
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $directory = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $directory "$leaf.bak.$stamp"
    $counter = 1
    while (Test-Path -LiteralPath $backup) {
        $backup = Join-Path $directory "$leaf.bak.$stamp-$counter"
        $counter++
    }

    Copy-Item -LiteralPath $Path -Destination $backup

    Get-ChildItem -LiteralPath $directory -Filter "$leaf.bak.*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $Retention |
        Remove-Item -Force

    return $backup
}

function Set-JsonProperty {
    param(
        $Object,
        [string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties[$Name]) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Merge-TerminalSettings {
    param(
        $Settings,
        $Template,
        [string]$DefaultProfileGuid
    )

    $changed = $false

    foreach ($property in $Template.PSObject.Properties) {
        switch ($property.Name) {
            'keybindings' {
                $bindings = @($Settings.keybindings)
                $bindingsChanged = $false
                foreach ($desired in @($property.Value)) {
                    $existing = $bindings | Where-Object { $_.id -eq $desired.id } | Select-Object -First 1
                    if ($existing) {
                        if ($existing.keys -ne $desired.keys) {
                            $existing.keys = $desired.keys
                            $bindingsChanged = $true
                        }
                    } else {
                        $bindings += $desired
                        $bindingsChanged = $true
                    }
                }
                if ($bindingsChanged) {
                    Set-JsonProperty -Object $Settings -Name 'keybindings' -Value @($bindings)
                    $changed = $true
                }
            }
            'newTabMenu' {
                $menu = @($Settings.newTabMenu)
                if (-not ($menu | Where-Object { $_.type -eq 'remainingProfiles' })) {
                    $menu += [pscustomobject]@{ type = 'remainingProfiles' }
                    Set-JsonProperty -Object $Settings -Name 'newTabMenu' -Value @($menu)
                    $changed = $true
                }
            }
            'profiles' {
                if (-not $Settings.profiles) {
                    Set-JsonProperty -Object $Settings -Name 'profiles' -Value ([pscustomobject]@{})
                }
                if (-not $Settings.profiles.defaults) {
                    Set-JsonProperty -Object $Settings.profiles -Name 'defaults' -Value ([pscustomobject]@{})
                }
                $desiredScheme = $property.Value.defaults.colorScheme
                $currentScheme = $Settings.profiles.defaults.colorScheme
                if (-not $currentScheme -or
                    $currentScheme.light -ne $desiredScheme.light -or
                    $currentScheme.dark -ne $desiredScheme.dark) {
                    Set-JsonProperty -Object $Settings.profiles.defaults -Name 'colorScheme' -Value $desiredScheme
                    $changed = $true
                }
            }
            default {
                if ($Settings.($property.Name) -ne $property.Value) {
                    Set-JsonProperty -Object $Settings -Name $property.Name -Value $property.Value
                    $changed = $true
                }
            }
        }
    }

    if ($DefaultProfileGuid -and $Settings.defaultProfile -ne $DefaultProfileGuid) {
        Set-JsonProperty -Object $Settings -Name 'defaultProfile' -Value $DefaultProfileGuid
        $changed = $true
    }

    return $changed
}

if ($Check -and $DryRun) {
    Write-Result -Status fail -Message 'use either -Check or -DryRun, not both'
    $exitCode = Show-Summary
    exit $exitCode
}

# --- .wslconfig --------------------------------------------------------------

Write-Section '.wslconfig'

$wslTemplatePath = Join-Path $PSScriptRoot 'settings\wslconfig'
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$desiredIni = Read-IniFile -Path $wslTemplatePath
$currentIni = @{}
if (Test-Path -LiteralPath $wslConfigPath) {
    $currentIni = Read-IniFile -Path $wslConfigPath
}

$wslChanges = @()
foreach ($section in $desiredIni.Keys) {
    foreach ($key in $desiredIni[$section].Keys) {
        $desired = $desiredIni[$section][$key]
        $current = $null
        if ($currentIni.ContainsKey($section) -and $currentIni[$section].ContainsKey($key)) {
            $current = $currentIni[$section][$key]
        }
        if ($current -ne $desired) {
            $wslChanges += [pscustomobject]@{
                Section = $section
                Key     = $key
                Current = $current
                Desired = $desired
            }
        }
    }
}

if ($wslChanges.Count -eq 0) {
    Write-Result -Status ok -Message '.wslconfig is up to date'
} else {
    foreach ($change in $wslChanges) {
        $current = if ($null -eq $change.Current) { 'unset' } else { $change.Current }
        Write-Info ".wslconfig [$($change.Section)] $($change.Key): $current -> $($change.Desired)"
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

$terminalChanged = $false
$settings = $null
if (-not $terminalPath) {
    Write-Result -Status fail -Message 'Windows Terminal settings not found; launch Terminal once'
} else {
    $templatePath = Join-Path $PSScriptRoot 'settings\terminal.json'
    try {
        $settings = Get-Content -LiteralPath $terminalPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Result -Status fail -Message "could not parse Terminal settings: $($_.Exception.Message)"
        $settings = $null
    }

    if ($settings) {
        $wslProfiles = @()
        if ($settings.profiles -and $settings.profiles.list) {
            $wslProfiles = @($settings.profiles.list | Where-Object { $_.source -eq 'Microsoft.WSL' })
        }

        $archProfile = $wslProfiles | Where-Object { $_.name -match 'arch' } | Select-Object -First 1
        $desiredProfile = if ($archProfile) { $archProfile } elseif ($wslProfiles.Count -gt 0) { $wslProfiles[0] } else { $null }
        $desiredProfileGuid = if ($desiredProfile) { $desiredProfile.guid } else { $null }

        if (-not $desiredProfile) {
            Write-Result -Status warn -Message 'no WSL profile found in Terminal settings; leaving defaultProfile unchanged'
        }

        $terminalChanged = Merge-TerminalSettings -Settings $settings -Template $template -DefaultProfileGuid $desiredProfileGuid

        if ($terminalChanged) {
            Write-Info "managed Terminal defaults differ from $terminalPath"
            if ($desiredProfile) {
                Write-Info "default profile will be set to $($desiredProfile.name)"
            }
        } else {
            Write-Result -Status ok -Message 'Terminal defaults are up to date'
        }
    }
}

# --- Apply -------------------------------------------------------------------

$needsChanges = ($wslChanges.Count -gt 0) -or $terminalChanged
if (-not $needsChanges) {
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

if ($Check) {
    Write-Info 'Check complete: settings need updates.'
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

if ($DryRun) {
    if ($wslChanges.Count -gt 0) {
        Write-Info "would back up and update $wslConfigPath"
    }
    if ($terminalChanged) {
        Write-Info "would back up and update $terminalPath"
    }
    Write-Info 'Dry run complete; no settings were changed.'
    Write-Section 'Summary'
    $exitCode = Show-Summary
    exit $exitCode
}

if (-not $Yes) {
    if ([Console]::IsInputRedirected) {
        Write-Result -Status fail -Message 'refusing to apply settings without -Yes when stdin is not a terminal'
        Write-Section 'Summary'
        $exitCode = Show-Summary
        exit $exitCode
    }

    $answer = Read-Host 'Apply Windows settings? [y/N]'
    if ($answer -notmatch '^[Yy]') {
        Write-Info 'Aborted.'
        exit 1
    }
}

if ($wslChanges.Count -gt 0) {
    $backup = Backup-ManagedFile -Path $wslConfigPath
    foreach ($change in $wslChanges) {
        Set-IniValue -Path $wslConfigPath -Section $change.Section -Key $change.Key -Value $change.Desired
    }
    if ($backup) {
        Write-Result -Status ok -Message "updated .wslconfig (backup: $backup)"
    } else {
        Write-Result -Status ok -Message 'created .wslconfig'
    }
}

if ($terminalChanged) {
    $backup = Backup-ManagedFile -Path $terminalPath
    $settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $terminalPath -Encoding UTF8
    if ($backup) {
        Write-Result -Status ok -Message "updated Terminal settings (backup: $backup)"
    } else {
        Write-Result -Status ok -Message 'updated Terminal settings'
    }
    Write-Info 'Windows Terminal hot-reloads settings.json; no restart is required.'
}

Write-Section 'Summary'
$exitCode = Show-Summary
exit $exitCode
