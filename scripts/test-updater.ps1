[CmdletBinding()]
param(
    [string]$JavaPath
)

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
    $extractNeoForge = $program.GetMethod('ExtractNeoForgeVersion', [System.Reflection.BindingFlags]'Static, NonPublic')
    $updateNeoForge = $program.GetMethod('UpdateNeoForgeManifest', [System.Reflection.BindingFlags]'Static, NonPublic')
    $migratePackwiz = $program.GetMethod('TryMigratePackwizCommand', [System.Reflection.BindingFlags]'Static, NonPublic')
    $needsShorterGamePath = $program.GetMethod('NeedsShorterGamePath', [System.Reflection.BindingFlags]'Static, NonPublic')
    $isSetupInstall = $program.GetMethod('IsSetupInstall', [System.Reflection.BindingFlags]'Static, NonPublic')
    if ($compare.Invoke($null, @('1.1.3-ely.2', '1.1.3-ely.1')) -le 0) {
        throw 'Updater version comparison test failed.'
    }
    if ($compare.Invoke($null, @('1.1.6-ely.2', '1.1.6-ely.1')) -le 0) {
        throw 'Updater must offer ely.2 to existing ely.1 installations.'
    }
    if ($compare.Invoke($null, @('1.1.6-ely.3', '1.1.6-ely.2')) -le 0) {
        throw 'Updater must offer ely.3 to existing ely.2 installations.'
    }
    if ($quote.Invoke($null, @('C:\Folder with spaces\file.exe')) -ne '"C:\Folder with spaces\file.exe"') {
        throw 'Updater Windows argument quoting test failed.'
    }
    $setupDetectionRoot = Join-Path $testRoot 'setup-detection'
    $newUninstaller = Join-Path $setupDetectionRoot 'uninstall\unins000.exe'
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $newUninstaller)) | Out-Null
    [System.IO.File]::WriteAllText($newUninstaller, 'test')
    $setupDetectionArguments = New-Object 'System.Object[]' 1
    $setupDetectionArguments[0] = $setupDetectionRoot.PSObject.BaseObject
    if (-not $isSetupInstall.Invoke($null, $setupDetectionArguments)) {
        throw 'Updater did not recognize the current Setup uninstall layout.'
    }
    Remove-Item -LiteralPath (Join-Path $setupDetectionRoot 'uninstall') -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $setupDetectionRoot 'unins000.exe'), 'test')
    if (-not $isSetupInstall.Invoke($null, $setupDetectionArguments)) {
        throw 'Updater did not recognize the legacy Setup uninstall layout.'
    }
    if (-not $needsShorterGamePath.Invoke($null, @('C:\Users\Example\AppData\Local\Programs\Blacked-Aeronautics-1.1.5-ely.1-win-x64-portable')) -or
        $needsShorterGamePath.Invoke($null, @('C:\Games\Blacked-Aeronautics'))) {
        throw 'Updater Distant Horizons path warning test failed.'
    }
    $samplePack = @'
[versions]
minecraft = "1.21.1"
neoforge = "21.1.238"

[options]
'@
    $packArguments = New-Object 'System.Object[]' 1
    $packArguments[0] = $samplePack.PSObject.BaseObject
    if ($extractNeoForge.Invoke($null, $packArguments) -ne '21.1.238') {
        throw 'Updater NeoForge version parser test failed.'
    }

    $instanceDirectory = Join-Path $testRoot 'instance'
    [System.IO.Directory]::CreateDirectory($instanceDirectory) | Out-Null
    $instanceManifest = Join-Path $instanceDirectory 'mmc-pack.json'
    Write-Utf8Json $instanceManifest ([ordered]@{
        components = @(
            [ordered]@{ uid = 'net.minecraft'; version = '1.21.1' },
            [ordered]@{ uid = 'net.neoforged'; version = '21.1.229'; cachedVersion = '21.1.229' }
        )
        formatVersion = 1
    })
    $manifestArguments = New-Object 'System.Object[]' 2
    $manifestArguments[0] = $instanceManifest.PSObject.BaseObject
    $manifestArguments[1] = '21.1.238'
    if (-not $updateNeoForge.Invoke($null, $manifestArguments)) {
        throw 'Updater NeoForge manifest test did not report a change.'
    }
    $updatedManifest = Get-Content -LiteralPath $instanceManifest -Raw | ConvertFrom-Json
    $updatedNeoForge = @($updatedManifest.components | Where-Object { $_.uid -eq 'net.neoforged' })[0]
    if ($updatedNeoForge.version -ne '21.1.238' -or $updatedNeoForge.cachedVersion -ne '21.1.238') {
        throw 'Updater NeoForge manifest test failed.'
    }
    if ($updateNeoForge.Invoke($null, $manifestArguments)) {
        throw 'Updater NeoForge manifest test reports a change for the current version.'
    }

    $migrationRoot = Join-Path $testRoot 'migration'
    $migrationInstance = Join-Path $migrationRoot 'instances\Blacked-Aeronautics'
    [System.IO.Directory]::CreateDirectory($migrationInstance) | Out-Null
    $migrationConfig = Join-Path $migrationInstance 'instance.cfg'
    $legacyCommand = 'PreLaunchCommand="\"$INST_JAVA\" -jar packwiz-installer-bootstrap.jar https://blacksoul1337.github.io/Blacked-Aeronautics/pack.toml"'
    [System.IO.File]::WriteAllText($migrationConfig, "[General]`n$legacyCommand`nMaxMemAlloc=6144`n")
    $migrationArguments = New-Object 'System.Object[]' 1
    $migrationArguments[0] = $migrationRoot.PSObject.BaseObject
    if (-not $migratePackwiz.Invoke($null, $migrationArguments)) {
        throw 'Updater packwiz command migration did not report a change.'
    }
    $migratedConfig = Get-Content -LiteralPath $migrationConfig -Raw
    if ($migratedConfig -notmatch '\$INST_MC_DIR/packwiz-update\.ps1' -or
        $migratedConfig -match 'packwiz-installer-bootstrap' -or
        $migratedConfig -notmatch 'MaxMemAlloc=6144') {
        throw 'Updater packwiz command migration failed.'
    }

    $relativeCommand = 'PreLaunchCommand="powershell.exe -NoProfile -NonInteractive ' +
        '-ExecutionPolicy Bypass -File packwiz-update.ps1 -JavaPath \"$INST_JAVA\""'
    [System.IO.File]::WriteAllText($migrationConfig, "[General]`n$relativeCommand`nMaxMemAlloc=7168`n")
    if (-not $migratePackwiz.Invoke($null, $migrationArguments)) {
        throw 'Updater relative packwiz command migration did not report a change.'
    }
    $migratedConfig = Get-Content -LiteralPath $migrationConfig -Raw
    if ($migratedConfig -notmatch '\$INST_MC_DIR/packwiz-update\.ps1' -or
        $migratedConfig -notmatch 'MaxMemAlloc=7168') {
        throw 'Updater relative packwiz command migration failed.'
    }

    $fakeJava = Join-Path $testRoot 'fake-java.exe'
    $fakeJavaSource = Join-Path $testRoot 'fake-java.cs'
    $fakeInstaller = Join-Path $testRoot 'packwiz-installer.jar'
    $fakeLog = Join-Path $testRoot 'packwiz-fallback.log'
    $fakeState = Join-Path $testRoot 'packwiz-fallback.state'
    [System.IO.File]::WriteAllText($fakeInstaller, 'test')
    [System.IO.File]::WriteAllText($fakeJavaSource, @'
using System;
using System.IO;

internal static class FakeJava
{
    private static int Main(string[] args)
    {
        string log = Environment.GetEnvironmentVariable("FAKE_JAVA_LOG");
        string state = Environment.GetEnvironmentVariable("FAKE_JAVA_STATE");
        File.AppendAllText(log, string.Join(" ", args) + Environment.NewLine);
        Console.WriteLine("fake packwiz output");
        if (File.Exists(state))
            return 0;
        File.WriteAllText(state, "failed once");
        return 23;
    }
}
'@)
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler '/nologo' '/target:exe' '/platform:x64' "/out:$fakeJava" $fakeJavaSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeJava -PathType Leaf)) {
        throw "Fake Java compilation failed with exit code $LASTEXITCODE."
    }
    $packwizScript = Join-Path $repoRoot 'launcher-template\instances\Blacked-Aeronautics\minecraft\packwiz-update.ps1'
    $packwizScriptContent = Get-Content -LiteralPath $packwizScript -Raw
    if ($packwizScriptContent -match '\[string\]\$InstallerPath\s*=\s*\(Join-Path\s+\$PSScriptRoot') {
        throw 'Packwiz installer path is evaluated before the script root fallback.'
    }
    $childCommand = "& '$($packwizScript.Replace("'", "''"))' -JavaPath '$($fakeJava.Replace("'", "''"))' " +
        "-InstallerPath '$($fakeInstaller.Replace("'", "''"))' " +
        "-PackUrls @('https://primary.invalid/pack.toml','https://mirror.invalid/pack.toml')"
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childCommand))
    $previousFakeLog = $env:FAKE_JAVA_LOG
    $previousFakeState = $env:FAKE_JAVA_STATE
    $previousErrorAction = $ErrorActionPreference
    try {
        $env:FAKE_JAVA_LOG = $fakeLog
        $env:FAKE_JAVA_STATE = $fakeState
        $ErrorActionPreference = 'Continue'
        $fallbackOutput = @(& powershell.exe @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            $encodedCommand
        ) 2>&1)
        $fallbackExitCode = $LASTEXITCODE
    }
    finally {
        $env:FAKE_JAVA_LOG = $previousFakeLog
        $env:FAKE_JAVA_STATE = $previousFakeState
        $ErrorActionPreference = $previousErrorAction
    }
    if ($fallbackExitCode -ne 0) {
        $fallbackOutput | Write-Host
        Get-Content -LiteralPath $fakeLog -ErrorAction SilentlyContinue | Write-Host
        Write-Host "Fake state exists: $(Test-Path -LiteralPath $fakeState)"
        throw "Packwiz fallback test failed with exit code $fallbackExitCode."
    }
    $fallbackLog = @(Get-Content -LiteralPath $fakeLog)
    if ($fallbackLog.Count -ne 2 -or
        $fallbackLog[0] -notmatch 'primary\.invalid' -or
        $fallbackLog[1] -notmatch 'mirror\.invalid' -or
        $fallbackLog[1] -notmatch 'java\.net\.useSystemProxies=true' -or
        $fallbackLog[1] -notmatch '-cp' -or
        $fallbackLog[1] -notmatch 'link\.infra\.packwiz\.installer\.Main' -or
        $fallbackLog[1] -match '-jar' -or
        $fallbackLog[1] -notmatch '--no-gui' -or
        $fallbackLog[1] -notmatch '--timeout 60') {
        throw 'Packwiz fallback did not try the primary source and mirror in order.'
    }
    if (($fallbackOutput -join "`n") -notmatch 'fake packwiz output') {
        throw 'Packwiz output is not forwarded to the launcher log.'
    }

    Remove-Item -LiteralPath $fakeLog, $fakeState -Force -ErrorAction SilentlyContinue
    $retryCommand = "& '$($packwizScript.Replace("'", "''"))' " +
        "-JavaPath '$($fakeJava.Replace("'", "''"))' " +
        "-InstallerPath '$($fakeInstaller.Replace("'", "''"))' " +
        "-PackUrls @('https://primary.invalid/pack.toml')"
    $encodedRetryCommand = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($retryCommand)
    )
    try {
        $env:FAKE_JAVA_LOG = $fakeLog
        $env:FAKE_JAVA_STATE = $fakeState
        $retryOutput = @(& powershell.exe @(
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            $encodedRetryCommand
        ) 2>&1)
        $retryExitCode = $LASTEXITCODE
    }
    finally {
        $env:FAKE_JAVA_LOG = $previousFakeLog
        $env:FAKE_JAVA_STATE = $previousFakeState
    }
    if ($retryExitCode -ne 0) {
        $retryOutput | Write-Host
        throw "Packwiz automatic retry test failed with exit code $retryExitCode."
    }
    $retryLog = @(Get-Content -LiteralPath $fakeLog)
    if ($retryLog.Count -ne 2 -or
        $retryLog[0] -notmatch 'primary\.invalid' -or
        $retryLog[1] -notmatch 'primary\.invalid') {
        throw 'Packwiz did not retry an incomplete first update automatically.'
    }

    $unicodeName = -join (@(
        0x043F, 0x0443, 0x0442, 0x044C, 0x0020, 0x0441, 0x0020,
        0x043A, 0x0438, 0x0440, 0x0438, 0x043B, 0x043B, 0x0438,
        0x0446, 0x0435, 0x0439
    ) | ForEach-Object { [char]$_ })
    $unicodeRoot = Join-Path $testRoot $unicodeName
    [System.IO.Directory]::CreateDirectory($unicodeRoot) | Out-Null
    $unicodePackwizScript = Join-Path $unicodeRoot 'packwiz-update.ps1'
    $unicodeFakeJava = Join-Path $unicodeRoot 'fake-java.exe'
    $unicodeInstaller = Join-Path $unicodeRoot 'packwiz-installer.jar'
    Copy-Item -LiteralPath $packwizScript -Destination $unicodePackwizScript
    Copy-Item -LiteralPath $fakeJava -Destination $unicodeFakeJava
    Copy-Item -LiteralPath $fakeInstaller -Destination $unicodeInstaller
    $pathResolutionLog = Join-Path $unicodeRoot 'packwiz-path-resolution.log'
    $pathResolutionState = Join-Path $unicodeRoot 'packwiz-path-resolution.state'
    [System.IO.File]::WriteAllText($pathResolutionState, 'succeed immediately')
    try {
        $env:FAKE_JAVA_LOG = $pathResolutionLog
        $env:FAKE_JAVA_STATE = $pathResolutionState
        Push-Location $testRoot
        try {
            $pathResolutionOutput = @(& powershell.exe @(
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                $unicodePackwizScript,
                '-JavaPath',
                $unicodeFakeJava,
                '-PackUrls',
                'https://primary.invalid/pack.toml'
            ) 2>&1)
            $pathResolutionExitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $env:FAKE_JAVA_LOG = $previousFakeLog
        $env:FAKE_JAVA_STATE = $previousFakeState
    }
    if ($pathResolutionExitCode -ne 0) {
        $pathResolutionOutput | Write-Host
        throw "Packwiz Unicode -File path test failed with exit code $pathResolutionExitCode."
    }
    $pathResolutionArgs = Get-Content -LiteralPath $pathResolutionLog -Raw
    if ($pathResolutionArgs -notmatch 'packwiz-installer\.jar') {
        throw 'Packwiz installer path did not resolve inside the Unicode script directory.'
    }

    $realJava = if ([string]::IsNullOrWhiteSpace($JavaPath)) {
        Join-Path $repoRoot 'jdk-21.0.11+10\bin\java.exe'
    }
    else {
        [System.IO.Path]::GetFullPath($JavaPath)
    }
    if (-not (Test-Path -LiteralPath $realJava -PathType Leaf)) {
        throw "Java executable was not found: $realJava"
    }
    $realInstaller = Join-Path $repoRoot 'launcher-template\instances\Blacked-Aeronautics\minecraft\packwiz-installer.jar'
    $missingPack = [uri](Join-Path $testRoot 'missing-pack.toml')
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $installerSmokeOutput = @(& $realJava '-cp' $realInstaller 'link.infra.packwiz.installer.Main' `
            '--no-gui' '--timeout' '1' $missingPack.AbsoluteUri 2>&1)
        $installerSmokeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $installerSmokeText = $installerSmokeOutput -join "`n"
    if ($installerSmokeExitCode -eq 0 -or
        $installerSmokeText -match 'must be run through packwiz-installer-bootstrap|ClassNotFoundException') {
        throw 'The bundled packwiz-installer direct invocation test failed.'
    }

    Write-Host 'Updater tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
