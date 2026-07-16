[CmdletBinding()]
param(
    [string]$SourceInstance = 'E:\Prism\PrismLauncher\instances\Aeronautics - Create Customised',
    [string]$DestinationPack = (Join-Path $PSScriptRoot '..\pack')
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

$modrinthIndexPath = Join-Path $sourceInstancePath 'mrpack\modrinth.index.json'
if (-not (Test-Path -LiteralPath $modrinthIndexPath -PathType Leaf)) {
    throw "Source Modrinth index is missing: $modrinthIndexPath"
}
$modrinthIndex = Get-Content -LiteralPath $modrinthIndexPath -Raw | ConvertFrom-Json

foreach ($file in $modrinthIndex.files) {
    $relativePath = [string]$file.path
    if (-not $relativePath.StartsWith('mods/', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $filename = [System.IO.Path]::GetFileName($relativePath)
    if ($filename -like 'e4mc-*') {
        continue
    }

    $sourceJar = Join-Path $sourceMinecraft $relativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $sourceJar -PathType Leaf)) {
        throw "A mod from the source index is not installed: $relativePath"
    }

    $url = [string]$file.downloads[0]
    $match = [regex]::Match($url, '/data/([^/]+)/versions/([^/]+)/')
    if (-not $match.Success) {
        throw "Could not read Modrinth project/version IDs from: $url"
    }

    $metadataParameters = @{
        OutputDirectory = $modsOutput
        Name = [System.IO.Path]::GetFileNameWithoutExtension($filename)
        Filename = $filename
        Url = $url
        Sha512 = [string]$file.hashes.sha512
        ProjectId = $match.Groups[1].Value
        VersionId = $match.Groups[2].Value
    }
    Write-ModrinthMetadata @metadataParameters
}

$additionalModrinthMods = @(
    [pscustomobject]@{
        Name = 'Allow Offline Players to Join LAN'
        Filename = 'allowofflinetojoinlan-1.0.0.jar'
        ProjectId = 'tNe7M4Fa'
        VersionId = 'CbaUUqoN'
        Sha512 = 'd0270bcf6c212881f3df0539d09dd0eb21775788fc7e9ad62365d5cf3096f8c18d5d2f6b60c9dc6ee0b1449ab7f56a8abef590cde56f7e980724c025fc90505d'
        Url = 'https://cdn.modrinth.com/data/tNe7M4Fa/versions/CbaUUqoN/allowofflinetojoinlan-1.0.0.jar'
    },
    [pscustomobject]@{
        Name = 'Quick Skin'
        Filename = 'Quick Skin - NeoForge - 1.21.1-2.6.2.4.jar'
        ProjectId = 'zAIE84Ch'
        VersionId = 'INuI60Al'
        Sha512 = '7f6eb037aba8df6110e30014217aee343a995f272ab781284c1387e93e15e30cdcd7364d2aaa755c1be7e291df2a484f52a581c100966c2239feeb20e41f964c'
        Url = 'https://cdn.modrinth.com/data/zAIE84Ch/versions/INuI60Al/Quick%20Skin%20-%20NeoForge%20-%201.21.1-2.6.2.4.jar'
    },
    [pscustomobject]@{
        Name = 'Ragdoll Corpse'
        Filename = 'ragdoll_corpse-1.21.1-0.3.0.jar'
        ProjectId = 'uetGbPKW'
        VersionId = 'DwA6a1pT'
        Sha512 = '1a65ea95bbaa171611f57a4ef448064a9f0d8c6a13f2d6ef56c1001ef0df469ff42eb471e3d6d6fe3e23141f57f09fae64cc18175db60e8e32bb792531ff82b4'
        Url = 'https://cdn.modrinth.com/data/uetGbPKW/versions/DwA6a1pT/ragdoll_corpse-1.21.1-0.3.0.jar'
    },
    [pscustomobject]@{
        Name = 'Ragdoll Reactions'
        Filename = 'ragdoll_reactions-1.21.1-0.7.0.jar'
        ProjectId = '6awFMFjR'
        VersionId = 'yx32Af0N'
        Sha512 = 'aab94063635d8790a33a9eb2191d7fc8b3b38b1b2885c0de96573ab3fbcb9a62b904f1512e6f39c3e13648b65b76f211f1b816608535174aac713b3d61364765'
        Url = 'https://cdn.modrinth.com/data/6awFMFjR/versions/yx32Af0N/ragdoll_reactions-1.21.1-0.7.0.jar'
    },
    [pscustomobject]@{
        Name = 'Sable Player Ragdoll'
        Filename = 'sable_player_ragdoll-1.21.1-0.7.5.jar'
        ProjectId = 'I3mWDgfy'
        VersionId = 'CyKh8XSr'
        Sha512 = 'c986f58bc4a4b0d47081e586a9d9c281096abf9c77bcde45f6ae1488e8120e71b79e019d2145ff0a392c5c168f5a8fb2b38907b1f5c6ab9d892622c55dac0ef9'
        Url = 'https://cdn.modrinth.com/data/I3mWDgfy/versions/CyKh8XSr/sable_player_ragdoll-1.21.1-0.7.5.jar'
    }
)

foreach ($mod in $additionalModrinthMods) {
    $sourceJar = Join-Path $sourceMinecraft ('mods\' + $mod.Filename)
    if (-not (Test-Path -LiteralPath $sourceJar -PathType Leaf)) {
        throw "Additional source mod is missing: $($mod.Filename)"
    }
    Write-ModrinthMetadata -OutputDirectory $modsOutput -Name $mod.Name -Filename $mod.Filename `
        -Url $mod.Url -Sha512 $mod.Sha512 -ProjectId $mod.ProjectId -VersionId $mod.VersionId
}

$createSalvageFilename = 'create_salvage-1.1.0+create6.0.10.jar'
$createSalvageSource = Join-Path $sourceMinecraft "mods\$createSalvageFilename"
if (-not (Test-Path -LiteralPath $createSalvageSource -PathType Leaf)) {
    throw "Create: Salvage source JAR is missing: $createSalvageSource"
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
if ($modMetadataCount -ne 161 -or $rawJarCount -ne 1) {
    throw "Unexpected imported mod count: $modMetadataCount Modrinth metadata files and $rawJarCount raw JARs."
}

Write-Host "Imported $modMetadataCount Modrinth mods, 1 MIT JAR, cleaned configs, KubeJS and Default Dark Mode."
