[CmdletBinding()]
param(
    [string]$Version = '1.1.3-ely.1',
    [string]$LauncherSource = (Join-Path $PSScriptRoot '..\elyprism'),
    [string]$JavaSource = (Join-Path $PSScriptRoot '..\jdk-21.0.11+10'),
    [string]$TemplateSource = (Join-Path $PSScriptRoot '..\launcher-template'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-ChildPath([string]$Child, [string]$Parent) {
    $childPath = Get-FullPath $Child
    $parentPath = (Get-FullPath $Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe output path: $childPath"
    }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination) {
    [System.IO.Directory]::CreateDirectory($Destination) | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

$repoRoot = Get-FullPath (Join-Path $PSScriptRoot '..')
$launcherPath = Get-FullPath $LauncherSource
$javaPath = Get-FullPath $JavaSource
$templatePath = Get-FullPath $TemplateSource
$outputRootPath = Get-FullPath $OutputRoot

foreach ($source in @($launcherPath, $javaPath, $templatePath)) {
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Required build source is missing: $source"
    }
}

$forbiddenLauncherSourceEntries = @(
    'accounts.json',
    'accounts.json.bak',
    'elyprismlauncher.cfg',
    'prismlauncher.cfg',
    'instances',
    'logs',
    'crash-reports',
    'cache',
    'metacache'
)
foreach ($entry in $forbiddenLauncherSourceEntries) {
    $candidate = Join-Path $launcherPath $entry
    if (Test-Path -LiteralPath $candidate) {
        throw "Launcher source contains local user data: $candidate"
    }
}
$launcherLog = Get-ChildItem -LiteralPath $launcherPath -Recurse -File -Force | Where-Object {
    $_.Extension -in @('.log', '.lck')
} | Select-Object -First 1
if ($launcherLog) {
    throw "Launcher source contains a local log or lock file: $($launcherLog.FullName)"
}

Assert-ChildPath $outputRootPath $repoRoot
[System.IO.Directory]::CreateDirectory($outputRootPath) | Out-Null

$artifactBaseName = "Blacked-Aeronautics-$Version-win-x64-portable"
$portableDirectory = Join-Path $outputRootPath $artifactBaseName
$archivePath = Join-Path $outputRootPath "$artifactBaseName.zip"
$staleSidecarPath = "$archivePath.sha256"
Assert-ChildPath $portableDirectory $outputRootPath
Assert-ChildPath $archivePath $outputRootPath
Assert-ChildPath $staleSidecarPath $outputRootPath

foreach ($generatedPath in @($portableDirectory, $archivePath, $staleSidecarPath)) {
    if (Test-Path -LiteralPath $generatedPath) {
        Remove-Item -LiteralPath $generatedPath -Recurse -Force
    }
}

Copy-DirectoryContents $launcherPath $portableDirectory
Copy-DirectoryContents $templatePath $portableDirectory
Copy-DirectoryContents $javaPath (Join-Path $portableDirectory 'java')
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md') -Destination $portableDirectory -Force
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $portableDirectory -Force

$wrapperExe = Join-Path $portableDirectory 'Blacked Aeronautics.exe'
& (Join-Path $PSScriptRoot 'build-updater.ps1') `
    -OutputPath $wrapperExe `
    -IconSource (Join-Path $portableDirectory 'elyprismlauncher.exe')
if ($LASTEXITCODE -ne 0) {
    throw "Updater build failed with exit code $LASTEXITCODE"
}

$updateConfig = [ordered]@{
    version = $Version
    repository = 'BlackSoul1337/Blacked-Aeronautics'
    launcher = 'elyprismlauncher.exe'
} | ConvertTo-Json
[System.IO.File]::WriteAllText(
    (Join-Path $portableDirectory 'blacked-update.json'),
    $updateConfig,
    [System.Text.UTF8Encoding]::new($false)
)

$launcherExe = Join-Path $portableDirectory 'elyprismlauncher.exe'
$javaExe = Join-Path $portableDirectory 'java\bin\java.exe'
$javawExe = Join-Path $portableDirectory 'java\bin\javaw.exe'
$bootstrapJar = Join-Path $portableDirectory 'instances\Blacked-Aeronautics\minecraft\packwiz-installer-bootstrap.jar'
$portableMarker = Join-Path $portableDirectory 'portable.txt'

foreach ($requiredFile in @($wrapperExe, $launcherExe, $javaExe, $javawExe, $bootstrapJar, $portableMarker)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Portable build is missing: $requiredFile"
    }
}

$forbiddenPortableFiles = @('accounts.json', 'accounts.json.bak', 'servers.dat', 'usercache.json')
$personalFile = Get-ChildItem -LiteralPath $portableDirectory -Recurse -File -Force | Where-Object {
    $_.Name.ToLowerInvariant() -in $forbiddenPortableFiles
} | Select-Object -First 1
if ($personalFile) {
    throw "Portable build contains personal data: $($personalFile.FullName)"
}

$launcherVersion = (Get-Item -LiteralPath $launcherExe).VersionInfo.ProductVersion
if ($launcherVersion -notlike '11.0.3*') {
    throw "Unexpected launcher version: $launcherVersion"
}

$javaRelease = Get-Content -LiteralPath (Join-Path $portableDirectory 'java\release') -Raw
if ($javaRelease -notmatch 'JAVA_VERSION="21\.0\.11"' -or $javaRelease -notmatch 'IMPLEMENTOR="Eclipse Adoptium"') {
    throw 'The portable Java runtime is not Eclipse Adoptium Temurin JDK 21.0.11.'
}

& $javaExe '-XX:+UseZGC' '-XX:+ZGenerational' '-XX:+AlwaysPreTouch' '-version'
if ($LASTEXITCODE -ne 0) {
    throw "Bundled Java compatibility check failed with exit code $LASTEXITCODE"
}

$configurationFiles = Get-ChildItem -LiteralPath $portableDirectory -Recurse -File | Where-Object {
    @('.cfg', '.json', '.toml', '.txt') -contains $_.Extension.ToLowerInvariant()
}
foreach ($file in $configurationFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match '(?i)([a-z]:\\users\\|e:\\prism\\prismlauncher)') {
        throw "Absolute local path leaked into the portable build: $($file.FullName)"
    }
}

$seedFiles = @(
    'elyprismlauncher.cfg',
    'instances/Blacked-Aeronautics/instance.cfg'
)
$manifestFiles = Get-ChildItem -LiteralPath $portableDirectory -Recurse -File -Force | ForEach-Object {
    $relativePath = $_.FullName.Substring($portableDirectory.TrimEnd('\', '/').Length + 1).Replace('\', '/')
    [ordered]@{
        path = $relativePath
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        mode = if ($relativePath -in $seedFiles) { 'seed' } else { 'replace' }
    }
}
$distributionManifest = [ordered]@{
    version = $Version
    files = @($manifestFiles)
} | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText(
    (Join-Path $portableDirectory 'distribution-manifest.json'),
    $distributionManifest,
    [System.Text.UTF8Encoding]::new($false)
)

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $portableDirectory -Recurse -File -Force | ForEach-Object {
        $relativeEntryName = $_.FullName.Substring($portableDirectory.TrimEnd('\', '/').Length + 1).Replace('\', '/')
        $entryName = "$artifactBaseName/$relativeEntryName"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $_.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $archive.Dispose()
}

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

Write-Host "Portable build created: $archivePath"
Write-Host "SHA-256: $archiveHash"
