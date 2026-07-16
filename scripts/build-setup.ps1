[CmdletBinding()]
param(
    [string]$Version = '1.1.3-ely.1',
    [string]$PortableDirectory,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\dist'),
    [string]$InnoCompiler
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

$repoRoot = Get-FullPath (Join-Path $PSScriptRoot '..')
$outputRootPath = Get-FullPath $OutputRoot
if ([string]::IsNullOrWhiteSpace($PortableDirectory)) {
    $PortableDirectory = Join-Path $outputRootPath "Blacked-Aeronautics-$Version-win-x64-portable"
}
$portablePath = Get-FullPath $PortableDirectory
$installerDefinition = Join-Path $repoRoot 'installer\Blacked-Aeronautics.iss'

foreach ($requiredFile in @(
    (Join-Path $portablePath 'Blacked Aeronautics.exe'),
    (Join-Path $portablePath 'elyprismlauncher.exe'),
    (Join-Path $portablePath 'java\bin\javaw.exe'),
    (Join-Path $portablePath 'portable.txt'),
    $installerDefinition
)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Setup input is missing: $requiredFile"
    }
}

[System.IO.Directory]::CreateDirectory($outputRootPath) | Out-Null

if ([string]::IsNullOrWhiteSpace($InnoCompiler)) {
    $command = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
    $candidates = @(
        $(if ($command) { $command.Source }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe' }),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe' }),
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $InnoCompiler = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($InnoCompiler) -or -not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) {
    throw 'Inno Setup 6 compiler (ISCC.exe) was not found. Install JRSoftware.InnoSetup with winget or pass -InnoCompiler.'
}

$setupBaseName = "Blacked-Aeronautics-$Version-win-x64-setup"
$setupPath = Join-Path $outputRootPath "$setupBaseName.exe"
$staleSidecarPath = "$setupPath.sha256"
foreach ($generatedPath in @($setupPath, $staleSidecarPath)) {
    if (Test-Path -LiteralPath $generatedPath -PathType Leaf) {
        Remove-Item -LiteralPath $generatedPath -Force
    }
}

$environmentNames = @('BLACKED_VERSION', 'BLACKED_PORTABLE_SOURCE', 'BLACKED_SETUP_OUTPUT')
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $item = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    $previousEnvironment[$name] = if ($item) { $item.Value } else { $null }
}

try {
    $env:BLACKED_VERSION = $Version
    $env:BLACKED_PORTABLE_SOURCE = $portablePath
    $env:BLACKED_SETUP_OUTPUT = $outputRootPath
    & $InnoCompiler $installerDefinition
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
    }
}
finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previousEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -LiteralPath "Env:$name" -Value $previousEnvironment[$name]
        }
    }
}

if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
    throw "Inno Setup did not create the expected file: $setupPath"
}

$setupHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Setup created: $setupPath"
Write-Host "SHA-256: $setupHash"
