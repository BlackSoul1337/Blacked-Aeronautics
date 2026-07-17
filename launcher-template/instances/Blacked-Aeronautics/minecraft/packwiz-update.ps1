[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,
    [string]$InstallerPath = (Join-Path $PSScriptRoot 'packwiz-installer.jar'),
    [string[]]$PackUrls = @(
        'https://blacksoul1337.github.io/Blacked-Aeronautics/pack.toml',
        'https://cdn.jsdelivr.net/gh/BlackSoul1337/Blacked-Aeronautics@main/pack/pack.toml'
    )
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$java = [System.IO.Path]::GetFullPath($JavaPath)
$installer = [System.IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $java -PathType Leaf)) {
    throw "Bundled Java was not found: $java"
}
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Bundled packwiz-installer was not found: $installer"
}
if ($PackUrls.Count -lt 1) {
    throw 'No pack sources are configured.'
}

$consoleJava = Join-Path (Split-Path -Parent $java) 'java.exe'
if (Test-Path -LiteralPath $consoleJava -PathType Leaf) {
    $java = $consoleJava
}

$lastExitCode = 1
Push-Location $PSScriptRoot
try {
    for ($index = 0; $index -lt $PackUrls.Count; $index++) {
        $packUrl = $PackUrls[$index]
        Write-Host "Updating Blacked Aeronautics from $packUrl"
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $java
        $startInfo.Arguments = '-Djava.net.useSystemProxies=true -jar "{0}" "{1}"' -f $installer, $packUrl
        $startInfo.WorkingDirectory = $PSScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $process.WaitForExit()
        $lastExitCode = $process.ExitCode
        $process.Dispose()
        Write-Host "Update source exit code: $lastExitCode"
        if ($lastExitCode -eq 0) {
            exit 0
        }
        if ($index + 1 -lt $PackUrls.Count) {
            Write-Warning 'The primary update source failed. Trying the mirror.'
        }
    }
}
finally {
    Pop-Location
}

Write-Error 'All Blacked Aeronautics update sources failed.' -ErrorAction Continue
exit $lastExitCode
