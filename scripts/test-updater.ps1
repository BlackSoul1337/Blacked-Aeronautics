[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Utf8Json([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function New-ManifestEntry([string]$Root, [string]$RelativePath, [string]$Mode) {
    $file = Join-Path $Root $RelativePath
    return [ordered]@{
        path = $RelativePath.Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        mode = $Mode
    }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$testRoot = Join-Path $repoRoot ('dist\updater-test-' + [guid]::NewGuid().ToString('N'))
$workRoot = Join-Path $testRoot 'work'
$stageRoot = Join-Path $workRoot 'Blacked-Aeronautics-test-win-x64-portable'
$targetRoot = Join-Path $testRoot 'target with spaces'
$helper = Join-Path $testRoot 'updater-helper.exe'
$testAssembly = Join-Path $repoRoot 'dist\updater-test.exe'

try {
    [System.IO.Directory]::CreateDirectory($stageRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($targetRoot) | Out-Null

    & (Join-Path $PSScriptRoot 'build-updater.ps1') -OutputPath $testAssembly
    Copy-Item -LiteralPath $testAssembly -Destination $helper -Force

    [System.IO.File]::WriteAllText((Join-Path $targetRoot 'replace.txt'), 'old')
    [System.IO.File]::WriteAllText((Join-Path $targetRoot 'remove.txt'), 'remove me')
    [System.IO.File]::WriteAllText((Join-Path $targetRoot 'settings.cfg'), 'player setting')
    [System.IO.File]::WriteAllText((Join-Path $targetRoot 'account-data.json'), 'keep me')

    $oldManifest = [ordered]@{
        version = '1.0.0'
        files = @(
            (New-ManifestEntry $targetRoot 'replace.txt' 'replace'),
            (New-ManifestEntry $targetRoot 'remove.txt' 'replace'),
            (New-ManifestEntry $targetRoot 'settings.cfg' 'seed')
        )
    }
    Write-Utf8Json (Join-Path $targetRoot 'distribution-manifest.json') $oldManifest

    [System.IO.File]::WriteAllText((Join-Path $stageRoot 'replace.txt'), 'new')
    [System.IO.File]::WriteAllText((Join-Path $stageRoot 'new.txt'), 'new file')
    [System.IO.File]::WriteAllText((Join-Path $stageRoot 'settings.cfg'), 'release default')
    $newManifest = [ordered]@{
        version = '1.1.0'
        files = @(
            (New-ManifestEntry $stageRoot 'replace.txt' 'replace'),
            (New-ManifestEntry $stageRoot 'new.txt' 'replace'),
            (New-ManifestEntry $stageRoot 'settings.cfg' 'seed')
        )
    }
    Write-Utf8Json (Join-Path $stageRoot 'distribution-manifest.json') $newManifest

    $process = Start-Process -FilePath $helper -ArgumentList @(
        '--apply-portable',
        ('"{0}"' -f $stageRoot),
        ('"{0}"' -f $targetRoot),
        '2147483646',
        ('"{0}"' -f $workRoot)
    ) -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Portable updater helper failed with exit code $($process.ExitCode)"
    }

    $assertions = @(
        @{ Pass = (Get-Content -LiteralPath (Join-Path $targetRoot 'replace.txt') -Raw) -eq 'new'; Message = 'replace file was not updated' },
        @{ Pass = (Get-Content -LiteralPath (Join-Path $targetRoot 'new.txt') -Raw) -eq 'new file'; Message = 'new file was not added' },
        @{ Pass = -not (Test-Path -LiteralPath (Join-Path $targetRoot 'remove.txt')); Message = 'removed file still exists' },
        @{ Pass = (Get-Content -LiteralPath (Join-Path $targetRoot 'settings.cfg') -Raw) -eq 'player setting'; Message = 'seed setting was overwritten' },
        @{ Pass = (Get-Content -LiteralPath (Join-Path $targetRoot 'account-data.json') -Raw) -eq 'keep me'; Message = 'unmanaged user file was changed' },
        @{ Pass = -not (Test-Path -LiteralPath $workRoot); Message = 'temporary update directory was not removed' }
    )
    foreach ($assertion in $assertions) {
        if (-not $assertion.Pass) {
            throw "Updater test failed: $($assertion.Message)"
        }
    }

    $assembly = [System.Reflection.Assembly]::LoadFile($testAssembly)
    $program = $assembly.GetType('BlackedAeronauticsUpdater.Program', $true)
    $compare = $program.GetMethod('CompareVersions', [System.Reflection.BindingFlags]'Static, NonPublic')
    $quote = $program.GetMethod('Quote', [System.Reflection.BindingFlags]'Static, NonPublic')
    if ($compare.Invoke($null, @('1.1.3-ely.2', '1.1.3-ely.1')) -le 0) {
        throw 'Updater version comparison test failed.'
    }
    if ($quote.Invoke($null, @('C:\Folder with spaces\file.exe')) -ne '"C:\Folder with spaces\file.exe"') {
        throw 'Updater Windows argument quoting test failed.'
    }

    Write-Host 'Updater tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
