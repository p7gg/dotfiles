#Requires -Version 7.0
# Dependency-free test for the managed Windows settings apply.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsScript = Join-Path $repoRoot 'provisioning\windows\settings.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-settings-test-' + [guid]::NewGuid().ToString('N'))
$oldUserProfile = $env:USERPROFILE
$oldLocalAppData = $env:LOCALAPPDATA
$failures = 0

function Assert-True {
    param(
        $Condition,
        [string]$Message
    )

    if (-not $Condition) {
        Write-Host "FAIL: $Message"
        $script:failures++
        return
    }
    Write-Host "ok: $Message"
}

try {
    $env:USERPROFILE = $root
    $env:LOCALAPPDATA = Join-Path $root 'AppData\Local'
    $terminalDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    New-Item -ItemType Directory -Force -Path $terminalDir | Out-Null

    $terminalPath = Join-Path $terminalDir 'settings.json'
    Set-Content -LiteralPath $terminalPath -Encoding UTF8 -Value @'
{
  "profiles": {
    "defaults": {},
    "list": [
      { "guid": "{1111}", "name": "archlinux", "source": "Microsoft.WSL" }
    ]
  },
  "keybindings": [],
  "newTabMenu": []
}
'@

    $wslPath = Join-Path $root '.wslconfig'
    Set-Content -LiteralPath $wslPath -Encoding UTF8 -Value @'
[wsl2]
memory=8GB
processors=4

[experimental]
autoMemoryReclaim=gradual
'@

    & $settingsScript -Yes -NoColor

    $ini = Get-Content -LiteralPath $wslPath -Raw
    Assert-True ($ini -match 'memory=24GB') 'settings updates memory'
    Assert-True ($ini -match 'swap=8GB') 'settings inserts swap'
    Assert-True ($ini -match 'processors=4') 'settings preserves sibling keys'
    Assert-True ($ini -match 'autoMemoryReclaim=gradual') 'settings preserves other sections'

    $json = Get-Content -LiteralPath $terminalPath -Raw | ConvertFrom-Json
    Assert-True ($json.defaultProfile -eq '{1111}') 'settings selects the WSL profile'
    Assert-True ($json.theme -eq 'system') 'settings sets the theme'
    Assert-True ($json.copyOnSelect -eq $false) 'settings sets copyOnSelect'
    Assert-True ($json.copyFormatting -eq 'none') 'settings sets copyFormatting'
    Assert-True ($json.profiles.defaults.colorScheme.dark -eq 'VSCode Dark Modern') 'settings sets the dark color scheme'
    Assert-True ($json.keybindings.Count -eq 4) 'settings merges keybindings'
    Assert-True ($json.newTabMenu.Count -eq 1) 'settings ensures the new-tab menu'

    Assert-True ((Get-ChildItem -LiteralPath $root -Filter '.wslconfig.bak.*').Count -eq 1) 'settings backs up .wslconfig'
    Assert-True ((Get-ChildItem -LiteralPath $terminalDir -Filter 'settings.json.bak.*').Count -eq 1) 'settings backs up Terminal settings'

    $checkOutput = & $settingsScript -Check -NoColor *>&1 | Out-String
    Assert-True ($checkOutput -match '\.wslconfig is up to date') 'settings check is clean after apply'
    Assert-True ($checkOutput -match 'Terminal defaults are up to date') 'Terminal check is clean after apply'
} finally {
    $env:USERPROFILE = $oldUserProfile
    $env:LOCALAPPDATA = $oldLocalAppData
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

if ($failures -gt 0) {
    exit 1
}

Write-Host 'windows settings tests passed'
