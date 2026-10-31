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

Assert-Equal 8589934592 (ConvertTo-WslBytes '8GB') 'parses gigabyte values'
Assert-Equal 25769803776 (ConvertTo-WslBytes '24GB') 'parses larger gigabyte values'
Assert-Equal 25769803776 (ConvertTo-WslBytes '25769803776') 'keeps byte counts'
Assert-True ($null -eq (ConvertTo-WslBytes 'not-a-size')) 'rejects invalid sizes'
Assert-Equal '3.0.3.0' (Format-Version4 '3.0.3') 'normalizes a three-part version'
Assert-Equal '3.0.3.0' (Format-Version4 'v3.0.3') 'strips a v prefix'
Assert-Equal '2.0.0.0' (Format-Version4 '2') 'pads a short version'

$windows = Get-WindowsInfo
Assert-True ($windows.Build -gt 0) 'Windows build is detected'
Assert-True ($windows.Architecture) 'Windows architecture is detected'

# --- Alias, install, and WSL mocks ------------------------------------------

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-windows-lib-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$statePath = Join-Path $testRoot 'winget-state.txt'
$fakeWinget = Join-Path $testRoot 'fake-winget.ps1'
$fakeWsl = Join-Path $testRoot 'fake-wsl.ps1'

Set-Content -LiteralPath $fakeWinget -Encoding UTF8 -Value @'
param(
    [Parameter(Position = 0)][string]$First,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest,
    [switch]$E
)

$Arguments = @()
if ($First) { $Arguments += $First }
$Arguments += $Rest
$statePath = $env:FAKE_WINGET_STATE
$command = $Arguments[0]

if ($command -eq '--version') {
    Write-Output 'v9.9.9'
    exit 0
}

if ($command -eq 'list') {
    $id = $null
    $name = $null
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '--id' { $id = $Arguments[$i + 1] }
            '--name' { $name = $Arguments[$i + 1] }
        }
    }

    $installed = @()
    if (Test-Path -LiteralPath $statePath) {
        $installed = @(Get-Content -LiteralPath $statePath)
    }

    if ($id -and $installed -contains "id:$id") {
        Write-Output 'Name Id Version'
        Write-Output '----------------'
        Write-Output "Fake $id 1.2.3"
        exit 0
    }

    if ($name -and $installed -contains "name:$name") {
        Write-Output 'Name Id Version'
        Write-Output '----------------'
        Write-Output "$name ARP\Fake 4.5.6"
        exit 0
    }

    exit 20
}

if ($command -eq 'install') {
    $id = $null
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -eq '--id') { $id = $Arguments[$i + 1] }
    }
    if ($id) {
        Add-Content -LiteralPath $statePath -Value "id:$id"
    }
    Add-Content -LiteralPath $statePath -Value "install-args:$($Arguments -join ' ')"
    Write-Output "installed $id"
    exit 0
}

exit 1
'@

Set-Content -LiteralPath $fakeWsl -Encoding UTF8 -Value @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
if ($Arguments[0] -eq '--version') {
    Write-Output 'WSL version: 9.9.9.0'
    Write-Output ''
    Write-Output 'Kernel version: 6.0.0-fake'
    exit 0
}
exit 1
'@

$oldState = $env:FAKE_WINGET_STATE
$env:FAKE_WINGET_STATE = $statePath

$aliases = @(Read-PackageAliasList -Path (Join-Path $repoRoot 'provisioning\windows\packages\aliases.txt'))
Assert-True (@($aliases | Where-Object { $_.Id -eq 'Spotify.Spotify' -and $_.Name -eq 'Spotify' }).Count -eq 1) 'Spotify alias is declared'
Assert-True (@(Get-PackageAliases -Id 'Spotify.Spotify') -contains 'Spotify') 'Spotify alias resolves'

Set-Content -LiteralPath $statePath -Value '' -Encoding UTF8
$missing = Get-InstalledWingetPackage -WingetPath $fakeWinget -Id 'Sample.Missing'
Assert-True $missing.Missing 'missing package is detected'
Assert-True (-not $missing.Installed) 'missing package is not installed'

Set-Content -LiteralPath $statePath -Value 'id:Sample.App' -Encoding UTF8
$installed = Get-InstalledWingetPackage -WingetPath $fakeWinget -Id 'Sample.App'
Assert-True $installed.Installed 'installed package is detected by id'
Assert-Equal 'id' $installed.MatchedBy 'installed package is matched by id'
Assert-Equal '1.2.3' $installed.Version 'installed package version is parsed'

Set-Content -LiteralPath $statePath -Value 'name:Spotify' -Encoding UTF8
$aliased = Get-InstalledWingetPackage -WingetPath $fakeWinget -Id 'Spotify.Spotify'
Assert-True $aliased.Installed 'store-installed package is detected by alias'
Assert-Equal 'alias' $aliased.MatchedBy 'aliased package is matched by alias'
Assert-Equal 'Spotify' $aliased.Alias 'aliased package records the alias'
Assert-Equal '4.5.6' $aliased.Version 'aliased package version is parsed'

$defaultArgs = @(Get-WingetInstallArgs -Id 'Sample.App')
Assert-True ($defaultArgs -contains '--silent') 'install args include --silent by default'
Assert-True ($defaultArgs -contains '--source') 'install args include the source'
Assert-True ($defaultArgs -contains 'winget') 'install args use the winget source'
$noSilentArgs = @(Get-WingetInstallArgs -Id 'Sample.App' -NoSilent)
Assert-True (-not ($noSilentArgs -contains '--silent')) 'install args omit --silent when requested'

Set-Content -LiteralPath $statePath -Value '' -Encoding UTF8
$installExit = Install-WingetPackage -WingetPath $fakeWinget -Id 'Sample.Install'
Assert-Equal 0 $installExit 'install returns the winget exit code'
$installState = @(Get-Content -LiteralPath $statePath)
Assert-True ($installState -contains 'id:Sample.Install') 'install records the package id'
$installArgsLine = $installState | Where-Object { $_ -like 'install-args:*' } | Select-Object -First 1
Assert-True ($installArgsLine -match '--silent') 'install passes --silent by default'

Set-Content -LiteralPath $statePath -Value '' -Encoding UTF8
$installExit = Install-WingetPackage -WingetPath $fakeWinget -Id 'Sample.Install' -NoSilent
Assert-Equal 0 $installExit 'install without silent returns the winget exit code'
$installArgsLine = @(Get-Content -LiteralPath $statePath) | Where-Object { $_ -like 'install-args:*' } | Select-Object -First 1
Assert-True (-not ($installArgsLine -match '--silent')) 'install omits --silent when requested'

$wsl = Get-WslVersion -WslPath $fakeWsl
Assert-True $wsl.Present 'fake wsl is present'
Assert-True $wsl.Usable 'fake wsl is usable'
Assert-Equal '9.9.9.0' $wsl.Version 'fake wsl version is parsed'

$iniPath = Join-Path $testRoot 'wslconfig'
Set-Content -LiteralPath $iniPath -Encoding UTF8 -Value @'
[wsl2]
memory=8GB
processors=4

[experimental]
autoMemoryReclaim=gradual
'@
Set-IniValue -Path $iniPath -Section 'wsl2' -Key 'memory' -Value '24GB'
Set-IniValue -Path $iniPath -Section 'wsl2' -Key 'swap' -Value '8GB'
$ini = Read-IniFile -Path $iniPath
Assert-Equal '24GB' $ini['wsl2']['memory'] 'ini merge updates an existing key'
Assert-Equal '8GB' $ini['wsl2']['swap'] 'ini merge inserts a new key'
Assert-Equal '4' $ini['wsl2']['processors'] 'ini merge preserves sibling keys'
Assert-Equal 'gradual' $ini['experimental']['autoMemoryReclaim'] 'ini merge preserves other sections'

if ($null -eq $oldState) {
    Remove-Item Env:\FAKE_WINGET_STATE -ErrorAction SilentlyContinue
} else {
    $env:FAKE_WINGET_STATE = $oldState
}
Remove-Item -LiteralPath $testRoot -Recurse -Force

if ($script:failures -gt 0) {
    exit 1
}

Write-Host 'windows lib tests passed'
