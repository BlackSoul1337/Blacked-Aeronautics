[CmdletBinding()]
param(
    [string]$SourceInstance = 'E:\Prism\PrismLauncher\instances\Aeronautics - Create Customised',
    [string]$DestinationPack = (Join-Path $PSScriptRoot '..\pack')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Get-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-ChildPath([string]$Child, [string]$Parent) {
    $childPath = Get-FullPath $Child
    $parentPath = (Get-FullPath $Parent).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside the expected root: $childPath"
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $encoding)
}

function Escape-Toml([string]$Value) {
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function ConvertTo-SafeName([string]$Value) {
    $result = $Value.ToLowerInvariant() -replace '[^a-z0-9._-]+', '-'
    return $result.Trim('-')
}

function Write-ModrinthMetadata {
    param(
        [string]$OutputDirectory,
        [string]$Name,
        [string]$Filename,
        [string]$Url,
        [string]$Sha512,
        [string]$ProjectId,
        [string]$VersionId,
        [ValidateSet('client', 'server', 'both')]
        [string]$Side = 'both'
    )

    if ($Sha512 -notmatch '^[0-9a-fA-F]{128}$') {
        throw "Invalid SHA-512 for $Filename"
    }
    if ($Url -notmatch '^https://cdn\.modrinth\.com/') {
        throw "Unexpected non-Modrinth URL for ${Filename}: $Url"
    }

    $baseName = ConvertTo-SafeName ([System.IO.Path]::GetFileNameWithoutExtension($Filename))
    $metadataPath = Join-Path $OutputDirectory "$ProjectId-$baseName.pw.toml"
    $content = @"
name = "$(Escape-Toml $Name)"
filename = "$(Escape-Toml $Filename)"
side = "$Side"

[download]
url = "$(Escape-Toml $Url)"
hash-format = "sha512"
hash = "$($Sha512.ToLowerInvariant())"

[update]
[update.modrinth]
mod-id = "$ProjectId"
version = "$VersionId"
"@
    Write-Utf8NoBom $metadataPath ($content.TrimStart() + "`n")
}

$repoRoot = Get-FullPath (Join-Path $PSScriptRoot '..')
$sourceInstancePath = Get-FullPath $SourceInstance
$destinationPackPath = Get-FullPath $DestinationPack
$sourceMinecraft = Join-Path $sourceInstancePath 'minecraft'

if (-not (Test-Path -LiteralPath $sourceMinecraft -PathType Container)) {
    throw "Source Minecraft directory was not found: $sourceMinecraft"
}
Assert-ChildPath $destinationPackPath $repoRoot
[System.IO.Directory]::CreateDirectory($destinationPackPath) | Out-Null

$generatedEntries = @('config', 'defaultconfigs', 'kubejs', 'global_packs', 'mods', 'resourcepacks', 'options.txt')
foreach ($entry in $generatedEntries) {
    $target = Join-Path $destinationPackPath $entry
    Assert-ChildPath $target $destinationPackPath
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

$excludedExactPaths = @(
    'config/voicechat/username-cache.json',
    'config/voicechat/player-volumes.properties',
    'config/quickskin_preferences.json',
    'config/one-click-join',
    'config/almostunified/debug.json',
    'config/almostunified/duplicates.json',
    'config/crash_assistant/modlist.json'
)

function Test-ExcludedRelativePath([string]$RelativePath) {
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized -match '(^|/)\.gitignore$') { return $true }
    if ($normalized -match '\.bak$') { return $true }
    if ($normalized -match '(^|/)(\.connector|\.index)(/|$)') { return $true }
    if ($normalized -like 'config/quickskin/uploads/*') { return $true }
    if ($normalized -like 'config/e4mc/*') { return $true }
    if ($normalized -match '^config/structurify/structurify_backup_.*\.json$') { return $true }
    if ($excludedExactPaths -contains $normalized) { return $true }
    return $false
}

foreach ($directoryName in @('config', 'defaultconfigs', 'kubejs', 'global_packs')) {
    $sourceDirectory = Join-Path $sourceMinecraft $directoryName
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Required source directory is missing: $sourceDirectory"
    }

    Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File | ForEach-Object {
        $relativeWithinDirectory = $_.FullName.Substring($sourceDirectory.Length).TrimStart('\', '/')
        $relativePath = ($directoryName + '/' + $relativeWithinDirectory.Replace('\', '/'))
        if (-not (Test-ExcludedRelativePath $relativePath)) {
            $targetPath = Join-Path $destinationPackPath $relativePath
            Assert-ChildPath $targetPath $destinationPackPath
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath)) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $targetPath -Force
        }
    }
}

$voiceChatClientPath = Join-Path $destinationPackPath 'config\voicechat\voicechat-client.properties'
if (Test-Path -LiteralPath $voiceChatClientPath -PathType Leaf) {
    $voiceChatClient = (Get-Content -LiteralPath $voiceChatClientPath -Raw).Replace("`r`n", "`n")
    $voiceChatClient = [regex]::Replace($voiceChatClient, '(?m)^onboarding_finished=.*$', 'onboarding_finished=false')
    $voiceChatClient = [regex]::Replace($voiceChatClient, '(?m)^microphone=.*$', 'microphone=')
    $voiceChatClient = [regex]::Replace($voiceChatClient, '(?m)^speaker=.*$', 'speaker=')
    Write-Utf8NoBom $voiceChatClientPath $voiceChatClient
}

$quickSkinClientPath = Join-Path $destinationPackPath 'config\quickskin-client.json'
if (Test-Path -LiteralPath $quickSkinClientPath -PathType Leaf) {
    $quickSkinClient = Get-Content -LiteralPath $quickSkinClientPath -Raw
    foreach ($property in @('activeSkinHash', 'activeCpmModelHash', 'activeCapeHash', 'playerOwnSkinHash')) {
        $quickSkinClient = [regex]::Replace(
            $quickSkinClient,
            '("' + [regex]::Escape($property) + '"\s*:\s*)"[^"]*"',
            '$1""'
        )
    }
    Write-Utf8NoBom $quickSkinClientPath $quickSkinClient
}

$kubeJsWebServerPath = Join-Path $destinationPackPath 'kubejs\config\web_server.json'
$safeKubeJsWebServer = @'
{
  "enabled": false,
  "port": 61423,
  "public_address": "",
  "auth": ""
}
'@
Write-Utf8NoBom $kubeJsWebServerPath ($safeKubeJsWebServer + "`n")

$sourceOptions = Join-Path $sourceMinecraft 'options.txt'
if (-not (Test-Path -LiteralPath $sourceOptions -PathType Leaf)) {
    throw "Source options.txt is missing: $sourceOptions"
}
$optionsContent = (Get-Content -LiteralPath $sourceOptions -Raw).Replace("`r`n", "`n")
$optionsContent = [regex]::Replace($optionsContent, '(?m)^lastServer:.*\n?', '')
Write-Utf8NoBom (Join-Path $destinationPackPath 'options.txt') $optionsContent

$modsOutput = Join-Path $destinationPackPath 'mods'
$resourcepacksOutput = Join-Path $destinationPackPath 'resourcepacks'
[System.IO.Directory]::CreateDirectory($modsOutput) | Out-Null
[System.IO.Directory]::CreateDirectory($resourcepacksOutput) | Out-Null

$createSalvageFilename = 'create_salvage-1.1.0+create6.0.10.jar'
$createSalvageSource = Join-Path $sourceMinecraft "mods\$createSalvageFilename"
if (-not (Test-Path -LiteralPath $createSalvageSource -PathType Leaf)) {
    throw "Create: Salvage source JAR is missing: $createSalvageSource"
}

$sourceModDirectory = Join-Path $sourceMinecraft 'mods'
$sourceModJars = @(
    Get-ChildItem -LiteralPath $sourceModDirectory -Filter '*.jar' -File |
        Where-Object { $_.Name -notlike 'e4mc-*' -and $_.Name -ne $createSalvageFilename } |
        Sort-Object Name
)
if ($sourceModJars.Count -eq 0) {
    throw "No Modrinth JARs were found in: $sourceModDirectory"
}

$jarsBySha1 = @{}
foreach ($sourceJar in $sourceModJars) {
    $sha1 = (Get-FileHash -LiteralPath $sourceJar.FullName -Algorithm SHA1).Hash.ToLowerInvariant()
    if ($jarsBySha1.ContainsKey($sha1)) {
        throw "Duplicate installed mod content: $($sourceJar.Name)"
    }
    $jarsBySha1[$sha1] = $sourceJar
}

$lookupBody = @{
    hashes = @($jarsBySha1.Keys | Sort-Object)
    algorithm = 'sha1'
} | ConvertTo-Json -Depth 4 -Compress
$lookupHeaders = @{
    'User-Agent' = 'BlackSoul1337/Blacked-Aeronautics (pack maintenance)'
}
$versionsByHash = Invoke-RestMethod -Method Post `
    -Uri 'https://api.modrinth.com/v2/version_files' `
    -ContentType 'application/json' `
    -Headers $lookupHeaders `
    -Body $lookupBody

$unmatched = New-Object System.Collections.Generic.List[string]
foreach ($sha1 in @($jarsBySha1.Keys | Sort-Object)) {
    $sourceJar = $jarsBySha1[$sha1]
    $versionProperty = $versionsByHash.PSObject.Properties[$sha1]
    if ($null -eq $versionProperty) {
        $unmatched.Add($sourceJar.Name)
        continue
    }

    $version = $versionProperty.Value
    $versionFile = @($version.files | Where-Object {
        $null -ne $_.hashes -and ([string]$_.hashes.sha1).ToLowerInvariant() -eq $sha1
    }) | Select-Object -First 1
    if ($null -eq $versionFile) {
        throw "Modrinth returned a version without the matching file: $($sourceJar.Name)"
    }

    Write-ModrinthMetadata -OutputDirectory $modsOutput `
        -Name ([string]$version.name) `
        -Filename $sourceJar.Name `
        -Url ([string]$versionFile.url) `
        -Sha512 ([string]$versionFile.hashes.sha512) `
        -ProjectId ([string]$version.project_id) `
        -VersionId ([string]$version.id)
}

if ($unmatched.Count -gt 0) {
    throw "Installed JARs are not available on Modrinth. Review their licenses and add them explicitly:`n$($unmatched -join "`n")"
}

$actualCreateSalvageHash = (Get-FileHash -LiteralPath $createSalvageSource -Algorithm SHA512).Hash.ToLowerInvariant()
$expectedCreateSalvageHash = 'fda9138c05586a6ee50dbea4b91f509e3a8051bdaf059ed2f227019e50b7462b4b8b2aab08a2e759e6b834061febe145dd2273c128cae9f01ac54f8fdc519093'
if ($actualCreateSalvageHash -ne $expectedCreateSalvageHash) {
    throw 'Create: Salvage JAR does not match the reviewed MIT-licensed binary.'
}
Copy-Item -LiteralPath $createSalvageSource -Destination (Join-Path $modsOutput $createSalvageFilename) -Force

$resourcePack = [pscustomobject]@{
    Name = 'Default Dark Mode'
    Filename = 'Default-Dark-Mode-1.20.2+-2025.5.0.zip'
    ProjectId = '6SLU7tS5'
    VersionId = 'S7URnfmp'
    Sha512 = 'f13e861a306df9bf752026f5e4f8b52a84065657c6dd4a90c41d19cbd1f72304f55d5968daf228f3d364fc076db909dece26c0bc3e454ae8d74d78e447f7a0e7'
    Url = 'https://cdn.modrinth.com/data/6SLU7tS5/versions/S7URnfmp/Default-Dark-Mode-1.20.2%2B-2025.5.0.zip'
}
Write-ModrinthMetadata -OutputDirectory $resourcepacksOutput -Name $resourcePack.Name `
    -Filename $resourcePack.Filename -Url $resourcePack.Url -Sha512 $resourcePack.Sha512 `
    -ProjectId $resourcePack.ProjectId -VersionId $resourcePack.VersionId -Side client

$modMetadataCount = @(Get-ChildItem -LiteralPath $modsOutput -Filter '*.pw.toml' -File).Count
$rawJarCount = @(Get-ChildItem -LiteralPath $modsOutput -Filter '*.jar' -File).Count
if ($modMetadataCount -ne $sourceModJars.Count -or $rawJarCount -ne 1) {
    throw "Unexpected imported mod count: $modMetadataCount Modrinth metadata files and $rawJarCount raw JARs."
}

Write-Host "Imported $modMetadataCount Modrinth mods, 1 MIT JAR, cleaned configs, KubeJS and Default Dark Mode."
