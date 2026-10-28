#Requires -Version 5.1
# Dependency-free tests for the shared Windows PowerShell helpers.
# Run from Windows CI or from WSL with pwsh.exe.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'provisioning\windows\lib\common.ps1')
Initialize-Output -NoColor

$script:failures = 0

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        Write-Host "FAIL: $Message (expected '$Expected', got '$Actual')"
        $script:failures++
        return
    }
    Write-Host "ok: $Message"
}

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

function Assert-Throws {
    param(
        [scriptblock]$Script,
        [string]$Message
    )

    try {
        & $Script | Out-Null
        Write-Host "FAIL: $Message (did not throw)"
        $script:failures++
    } catch {
        Write-Host "ok: $Message"
    }
}

$categories = @(Get-OptionalCategories)
Assert-Equal 3 $categories.Count 'three optional categories'
Assert-True ($categories -contains 'apps') 'apps category exists'
Assert-True ($categories -contains 'games') 'games category exists'
Assert-True ($categories -contains 'hardware') 'hardware category exists'

$apps = @(Get-OptionalPackages -Categories @('apps'))
Assert-True ($apps.Count -gt 0) 'apps category has packages'
Assert-True (@($apps | Where-Object { $_.Id -eq 'Brave.Brave' }).Count -eq 1) 'apps includes Brave.Brave'
Assert-True (@($apps | Where-Object { $_.Category -ne 'apps' }).Count -eq 0) 'apps packages are tagged apps'

$expected = 0
foreach ($category in $categories) {
    $path = Join-Path $repoRoot "provisioning\windows\packages\optional\$category.txt"
    $expected += @(Read-PackageList -Path $path).Count
}

$all = @(Get-OptionalPackages -Categories @('all'))
Assert-Equal $expected $all.Count 'all expands to every optional package'
Assert-Throws { Get-OptionalPackages -Categories @('nope') } 'unknown optional category throws'

Assert-Equal '3.0.3.0' (Format-Version4 '3.0.3') 'normalizes a three-part version'
Assert-Equal '3.0.3.0' (Format-Version4 'v3.0.3') 'strips a v prefix'
Assert-Equal '2.0.0.0' (Format-Version4 '2') 'pads a short version'

$windows = Get-WindowsInfo
Assert-True ($windows.Build -gt 0) 'Windows build is detected'
Assert-True ($windows.Architecture) 'Windows architecture is detected'

if ($script:failures -gt 0) {
    exit 1
}

Write-Host 'windows lib tests passed'
