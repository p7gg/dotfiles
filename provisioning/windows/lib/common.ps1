# Shared helpers for the Windows provisioning scripts.
#
# Dot-source this file from audit.ps1 and bootstrap.ps1. It intentionally
# contains no top-level provisioning actions.

function Initialize-Output {
    param([switch]$NoColor)

    $script:NoColor = [bool]$NoColor
    $script:Checks = 0
    $script:Warnings = 0
    $script:Failures = 0
    $script:PackageAliasCache = $null
}

function Write-Info {
    param([string]$Message)

    Write-Host "       $Message"
}

function Write-Result {
    param(
        [ValidateSet('ok', 'warn', 'fail')]
        [string]$Status,
        [string]$Message
    )

    $script:Checks++

    switch ($Status) {
        'ok' { $color = 'Green' }
        'warn' { $color = 'Yellow'; $script:Warnings++ }
        'fail' { $color = 'Red'; $script:Failures++ }
    }

    $label = "[$Status]"
    $line = '{0,-7} {1}' -f $label, $Message
    if ($script:NoColor) {
        Write-Host $line
    } else {
        Write-Host $line -ForegroundColor $color
    }
}

function Write-Section {
    param([string]$Title)

    Write-Host ''
    Write-Host $Title
    Write-Host ('-' * $Title.Length)
}

function Show-Summary {
    param([switch]$Strict)

    if ($Strict -and $script:Warnings -gt 0) {
        $script:Failures += $script:Warnings
    }

    $ok = $script:Checks - $script:Warnings - $script:Failures
    if ($ok -lt 0) {
        $ok = 0
    }
    Write-Info "$($script:Checks) checks: $ok ok, $($script:Warnings) warning(s), $($script:Failures) failure(s)"

    if ($script:Failures -gt 0) {
        if ($Strict -and $script:Warnings -gt 0 -and $script:Failures -eq $script:Warnings) {
            Write-Info 'Strict mode treats warnings as failures.'
        }
        return 1
    }

    return 0
}

function Read-PackageList {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Result -Status fail -Message "missing package list: $Path"
        return @()
    }

    $packages = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $value = ($line -replace '#.*$', '').Trim()
        if (-not $value) {
            continue
        }
        if ($value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            Write-Result -Status fail -Message "invalid package ID in $(Split-Path -Leaf $Path): $value"
            continue
        }
        $packages += $value
    }

    return $packages
}

function Read-PackageAliasList {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $aliases = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $value = ($line -replace '#.*$', '').Trim()
        if (-not $value) {
            continue
        }

        $parts = $value -split '\|', 2
        if ($parts.Count -ne 2 -or -not $parts[0].Trim() -or -not $parts[1].Trim()) {
            Write-Result -Status fail -Message "invalid alias entry in $(Split-Path -Leaf $Path): $value"
            continue
        }

        $aliases += [pscustomobject]@{
            Id   = $parts[0].Trim()
            Name = $parts[1].Trim()
        }
    }

    return $aliases
}

function Get-PackageAliases {
    param([string]$Id)

    if ($null -eq $script:PackageAliasCache) {
        $path = Join-Path $PSScriptRoot '..\packages\aliases.txt'
        $script:PackageAliasCache = @(Read-PackageAliasList -Path $path)
    }

    return @(
        $script:PackageAliasCache |
            Where-Object { $_.Id -eq $Id } |
            ForEach-Object { $_.Name }
    )
}

function Get-OptionalCategories {
    $directory = Join-Path $PSScriptRoot '..\packages\optional'
    if (-not (Test-Path -LiteralPath $directory)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $directory -Filter '*.txt' -File |
            ForEach-Object { $_.BaseName } |
            Sort-Object
    )
}

function Get-OptionalPackages {
    param([string[]]$Categories)

    $directory = Join-Path $PSScriptRoot '..\packages\optional'
    $available = @(Get-OptionalCategories)

    if ($Categories.Count -eq 0) {
        return @()
    }

    if ($Categories -contains 'all') {
        $Categories = $available
    }

    $unknown = @($Categories | Where-Object { $available -notcontains $_ })
    if ($unknown.Count -gt 0) {
        throw "unknown optional category: $($unknown -join ', ') (available: $($available -join ', '))"
    }

    $packages = @()
    foreach ($category in $Categories) {
        $path = Join-Path $directory "$category.txt"
        foreach ($id in @(Read-PackageList -Path $path)) {
            $packages += [pscustomobject]@{
                Id       = $id
                Category = $category
            }
        }
    }

    return $packages
}

function Get-WindowsInfo {
    $currentVersion = Get-ItemProperty `
        -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -ErrorAction SilentlyContinue
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

    $caption = if ($os) { $os.Caption } else { 'Windows' }
    $version = if ($currentVersion) { $currentVersion.DisplayVersion } else { '' }
    $build = if ($currentVersion) { [int]($currentVersion.CurrentBuildNumber) } else { 0 }
    $architecture = if ($os) { $os.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }

    return [pscustomobject]@{
        Caption      = $caption
        Version      = $version
        Build        = $build
        Architecture = $architecture
    }
}

function Get-WingetPath {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        return $winget.Source
    }

    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Get-WingetInstallArgs {
    param(
        [string]$Id,
        [switch]$NoSilent
    )

    $arguments = @(
        'install',
        '--id', $Id,
        '-e',
        '--source', 'winget',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    if (-not $NoSilent) {
        $arguments += '--silent'
    }

    return $arguments
}

function Install-WingetPackage {
    param(
        [string]$WingetPath,
        [string]$Id,
        [switch]$NoSilent
    )

    $arguments = Get-WingetInstallArgs -Id $Id -NoSilent:$NoSilent
    & $WingetPath @arguments | Out-Host
    return $LASTEXITCODE
}

function Get-InstalledWingetPackage {
    param(
        [string]$WingetPath,
        [string]$Id
    )

    # WinGet returns 0x8A150014 when no installed package matches. PowerShell
    # surfaces it as a signed Int32; older wrappers may only see the low byte.
    $noPackageExitCode = [int32]0x8A150014
    $output = @()
    $exitCode = $null

    # WinGet can fail transiently when another query holds its source lock.
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $output = & $WingetPath list --id $Id -e --accept-source-agreements --disable-interactivity 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0 -or $exitCode -eq 20 -or $exitCode -eq $noPackageExitCode) {
            break
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 500
        }
    }

    $text = ($output | Out-String)

    if ($exitCode -eq 0) {
        $version = ''
        if ($text -match ([regex]::Escape($Id) + '\s+(\S+)')) {
            $version = $Matches[1]
        }
        return [pscustomobject]@{
            Id        = $Id
            Installed = $true
            Missing   = $false
            MatchedBy = 'id'
            Alias     = $null
            Version   = $version
            ExitCode  = $exitCode
            Output    = $text.Trim()
        }
    }

    if ($exitCode -eq 20 -or $exitCode -eq $noPackageExitCode) {
        foreach ($alias in @(Get-PackageAliases -Id $Id)) {
            $aliasOutput = @()
            $aliasExitCode = $null

            for ($attempt = 1; $attempt -le 2; $attempt++) {
                $aliasOutput = & $WingetPath list --name $alias -e --accept-source-agreements --disable-interactivity 2>&1
                $aliasExitCode = $LASTEXITCODE
                if ($aliasExitCode -eq 0 -or $aliasExitCode -eq 20 -or $aliasExitCode -eq $noPackageExitCode) {
                    break
                }
                if ($attempt -lt 2) {
                    Start-Sleep -Milliseconds 500
                }
            }

            if ($aliasExitCode -eq 0) {
                $aliasText = ($aliasOutput | Out-String)
                $version = ''
                $lastLine = $aliasOutput | Where-Object { $_ -match '\S' } | Select-Object -Last 1
                if ($lastLine -and $lastLine -match '(\S+)\s*$') {
                    $version = $Matches[1]
                }
                return [pscustomobject]@{
                    Id        = $Id
                    Installed = $true
                    Missing   = $false
                    MatchedBy = 'alias'
                    Alias     = $alias
                    Version   = $version
                    ExitCode  = $aliasExitCode
                    Output    = $aliasText.Trim()
                }
            }
        }

        return [pscustomobject]@{
            Id        = $Id
            Installed = $false
            Missing   = $true
            MatchedBy = 'none'
            Alias     = $null
            Version   = ''
            ExitCode  = $exitCode
            Output    = $text.Trim()
        }
    }

    return [pscustomobject]@{
        Id        = $Id
        Installed = $false
        Missing   = $false
        MatchedBy = 'error'
        Alias     = $null
        Version   = ''
        ExitCode  = $exitCode
        Output    = $text.Trim()
    }
}

function Test-PendingReboot {
    $pending = $false

    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $pending = $true
    }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $pending = $true
    }

    $sessionManager = Get-ItemProperty `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name 'PendingFileRenameOperations' `
        -ErrorAction SilentlyContinue
    if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
        $pending = $true
    }

    return $pending
}

function Get-WslVersion {
    param([string]$WslPath)

    if (-not $WslPath) {
        $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        if (-not $wsl) {
            return [pscustomobject]@{
                Present  = $false
                Usable   = $false
                Version  = $null
                ExitCode = $null
                Output   = ''
            }
        }
        $WslPath = $wsl.Source
    }

    $output = (& $WslPath --version 2>&1) -replace "`0", ''
    $exitCode = $LASTEXITCODE
    $version = $null
    $line = $output | Select-Object -First 1
    if ($line -match 'WSL version:\s*(\S+)') {
        $version = $Matches[1]
    }

    return [pscustomobject]@{
        Present  = $true
        Usable   = ($exitCode -eq 0)
        Version  = $version
        ExitCode = $exitCode
        Output   = ($output -join "`n")
    }
}

function Test-FontInstalled {
    param([string]$Face)

    $keys = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )

    foreach ($key in $keys) {
        $properties = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if (-not $properties) {
            continue
        }
        foreach ($name in $properties.PSObject.Properties.Name) {
            if ($name -like "$Face*") {
                return $true
            }
        }
    }

    return $false
}

function Read-IniFile {
    param([string]$Path)

    $result = @{}
    $section = ''
    foreach ($line in Get-Content -LiteralPath $Path) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith(';') -or $value.StartsWith('#')) {
            continue
        }
        if ($value -match '^\[(.+)\]$') {
            $section = $Matches[1]
            if (-not $result.ContainsKey($section)) {
                $result[$section] = @{}
            }
            continue
        }
        if ($value -match '^([^=]+)=(.*)$') {
            if (-not $result.ContainsKey($section)) {
                $result[$section] = @{}
            }
            $result[$section][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    return $result
}

function Set-IniValue {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )

    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $lines = @(Get-Content -LiteralPath $Path)
    }

    $sectionPattern = '^\s*\[' + [regex]::Escape($Section) + '\]\s*$'
    $sectionAnyPattern = '^\s*\['
    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $sectionIndex = -1
    $keyIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $sectionPattern) {
            $sectionIndex = $i
            break
        }
    }

    if ($sectionIndex -ge 0) {
        for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $sectionAnyPattern) {
                break
            }
            if ($lines[$i] -match $keyPattern) {
                $keyIndex = $i
                break
            }
        }
    }

    $newLine = "$Key=$Value"
    if ($keyIndex -ge 0) {
        $lines[$keyIndex] = $newLine
    } elseif ($sectionIndex -ge 0) {
        $list = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $lines) {
            $list.Add($line)
        }
        $list.Insert($sectionIndex + 1, $newLine)
        $lines = $list.ToArray()
    } else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') {
            $lines += ''
        }
        $lines += "[$Section]"
        $lines += $newLine
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function ConvertTo-WslBytes {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    if ($Value -notmatch '^\s*(\d+)\s*([KMGT]i?B?)?\s*$') {
        return $null
    }

    $amount = [int64]$Matches[1]
    $unit = if ($null -eq $Matches[2]) { '' } else { $Matches[2].ToUpperInvariant() }
    switch ($unit) {
        'KB' { return $amount * 1KB }
        'KIB' { return $amount * 1KB }
        'K' { return $amount * 1KB }
        'MB' { return $amount * 1MB }
        'MIB' { return $amount * 1MB }
        'M' { return $amount * 1MB }
        'GB' { return $amount * 1GB }
        'GIB' { return $amount * 1GB }
        'G' { return $amount * 1GB }
        'TB' { return $amount * 1TB }
        'TIB' { return $amount * 1TB }
        'T' { return $amount * 1TB }
        default { return $amount }
    }
}

function Format-WslValue {
    param([string]$Value)

    if ($Value -match '^\d+$') {
        $bytes = [int64]$Value
        $gib = [math]::Round($bytes / 1GB, 1)
        return "$Value ($gib GiB)"
    }

    return $Value
}

function Format-Version4 {
    param([string]$Value)

    $parts = ($Value -replace '^v', '').Split('.')
    $normalized = @()
    for ($i = 0; $i -lt 4; $i++) {
        if ($i -lt $parts.Count -and $parts[$i] -match '^\d+$') {
            $normalized += $parts[$i]
        } else {
            $normalized += '0'
        }
    }

    return ($normalized -join '.')
}
