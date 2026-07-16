[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\updater\BlackedAeronauticsUpdater.cs'),
    [string]$IconSource,
    [string]$CompilerPath = (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$source = [System.IO.Path]::GetFullPath($SourcePath)
$output = [System.IO.Path]::GetFullPath($OutputPath)
$compiler = [System.IO.Path]::GetFullPath($CompilerPath)

foreach ($requiredFile in @($source, $compiler)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Updater build input is missing: $requiredFile"
    }
}

$outputDirectory = Split-Path -Parent $output
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

$references = @(
    'System.dll',
    'System.Core.dll',
    'System.Drawing.dll',
    'System.Windows.Forms.dll',
    'System.Web.Extensions.dll',
    'System.IO.Compression.dll',
    'System.IO.Compression.FileSystem.dll'
)
$arguments = @(
    '/nologo',
    '/target:winexe',
    '/platform:x64',
    '/optimize+',
    "/out:$output"
) + ($references | ForEach-Object { "/reference:$_" }) + @($source)

$temporaryIcon = $null
try {
    if (-not [string]::IsNullOrWhiteSpace($IconSource)) {
        $iconPath = [System.IO.Path]::GetFullPath($IconSource)
        if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
            throw "Updater icon source is missing: $iconPath"
        }
        Add-Type -AssemblyName System.Drawing
        $temporaryIcon = Join-Path ([System.IO.Path]::GetTempPath()) ('blacked-aeronautics-' + [guid]::NewGuid().ToString('N') + '.ico')
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
        if ($null -eq $icon) {
            throw "Could not extract updater icon from: $iconPath"
        }
        try {
            $stream = [System.IO.File]::Create($temporaryIcon)
            try { $icon.Save($stream) } finally { $stream.Dispose() }
        }
        finally {
            $icon.Dispose()
        }
        $arguments += "/win32icon:$temporaryIcon"
    }

    & $compiler $arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) {
        throw "Updater compilation failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($temporaryIcon -and (Test-Path -LiteralPath $temporaryIcon -PathType Leaf)) {
        Remove-Item -LiteralPath $temporaryIcon -Force
    }
}

Write-Host "Updater created: $output"
