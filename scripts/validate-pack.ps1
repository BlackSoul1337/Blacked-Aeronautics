[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path $PSScriptRoot '..\pack')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packRootFullPath = [System.IO.Path]::GetFullPath($PackRoot)
$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure([string]$Message) {
    $script:failures.Add($Message)
}

function Get-RelativePackPath([string]$FullName) {
    return $FullName.Substring($packRootFullPath.TrimEnd('\', '/').Length + 1).Replace('\', '/')
}

if (-not (Test-Path -LiteralPath $packRootFullPath -PathType Container)) {
    throw "Pack directory was not found: $packRootFullPath"
}

$packTomlPath = Join-Path $packRootFullPath 'pack.toml'
$indexPath = Join-Path $packRootFullPath 'index.toml'
if (-not (Test-Path -LiteralPath $packTomlPath -PathType Leaf)) { Add-Failure 'pack.toml is missing.' }
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { Add-Failure 'index.toml is missing.' }

$allFiles = @(Get-ChildItem -LiteralPath $packRootFullPath -Recurse -File -Force)
foreach ($file in $allFiles) {
    $relativePath = Get-RelativePackPath $file.FullName
    $lowerPath = $relativePath.ToLowerInvariant()
    if ($lowerPath -match '(^|/)(saves|logs|\.connector|\.index)(/|$)' -or
        $lowerPath -match '(^|/)distant_horizons_server_data(/|$)' -or
        $lowerPath -match '(^|/)(servers\.dat|mods\.rar|username-cache\.json|player-volumes\.properties)$' -or
        $lowerPath -match '\.sqlite(?:-wal|-shm)?$' -or
        $lowerPath -match '\.bak$' -or
        $lowerPath -match '^config/one-click-join$' -or
        $lowerPath -match '^config/structurify/structurify_backup_.*\.json$' -or
        $lowerPath -match '^config/quickskin/uploads/') {
        Add-Failure "Forbidden personal/cache file is present: $relativePath"
    }
    if ($lowerPath -match 'e4mc') {
        Add-Failure "e4mc must not be included: $relativePath"
    }
}

$distantHorizonsPath = Join-Path $packRootFullPath 'config\DistantHorizons.toml'
if (-not (Test-Path -LiteralPath $distantHorizonsPath -PathType Leaf)) {
    Add-Failure 'Distant Horizons config is missing.'
}
else {
    $distantHorizons = Get-Content -LiteralPath $distantHorizonsPath -Raw
    foreach ($setting in @('synchronizeOnLoad', 'enableServerGeneration', 'enableRealTimeUpdates')) {
        if ($distantHorizons -notmatch ('(?m)^\s*' + [regex]::Escape($setting) + '\s*=\s*false\s*\r?$')) {
            Add-Failure "Distant Horizons LOD sharing must stay disabled: $setting"
        }
    }
}

$voiceChatClientPath = Join-Path $packRootFullPath 'config\voicechat\voicechat-client.properties'
if (Test-Path -LiteralPath $voiceChatClientPath -PathType Leaf) {
    $voiceChatClient = Get-Content -LiteralPath $voiceChatClientPath -Raw
    foreach ($expectedSetting in @('onboarding_finished=false', 'microphone=', 'speaker=')) {
        if ($voiceChatClient -notmatch ('(?m)^' + [regex]::Escape($expectedSetting) + '\r?$')) {
            Add-Failure "Voice chat contains a personal device/onboarding value instead of: $expectedSetting"
        }
    }
}

$quickSkinClientPath = Join-Path $packRootFullPath 'config\quickskin-client.json'
if (Test-Path -LiteralPath $quickSkinClientPath -PathType Leaf) {
    $quickSkinClient = Get-Content -LiteralPath $quickSkinClientPath -Raw
    foreach ($property in @('activeSkinHash', 'activeCpmModelHash', 'activeCapeHash', 'playerOwnSkinHash')) {
        if ($quickSkinClient -notmatch ('"' + [regex]::Escape($property) + '"\s*:\s*""')) {
            Add-Failure "Quick Skin contains a personal value in $property."
        }
    }
}

$kubeJsWebServerPath = Join-Path $packRootFullPath 'kubejs\config\web_server.json'
if (Test-Path -LiteralPath $kubeJsWebServerPath -PathType Leaf) {
    $kubeJsWebServer = Get-Content -LiteralPath $kubeJsWebServerPath -Raw
    if ($kubeJsWebServer -notmatch '"enabled"\s*:\s*false' -or $kubeJsWebServer -notmatch '"auth"\s*:\s*""') {
        Add-Failure 'KubeJS web server must be disabled and contain no copied authentication secret.'
    }
}

$atlasCreativeBypassPath = Join-Path $packRootFullPath 'kubejs\client_scripts\atlasCreativeBypass.js'
if (Test-Path -LiteralPath $atlasCreativeBypassPath -PathType Leaf) {
    Add-Failure 'The obsolete Antique Atlas creative key handler must stay excluded.'
}

$textExtensions = @('.toml', '.json', '.json5', '.cfg', '.conf', '.properties', '.txt', '.js', '.md', '.yml', '.yaml', '.mcmeta')
foreach ($file in $allFiles | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() }) {
    try {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        if ($content -match '(?i)([a-z]:\\users\\|e:\\prism\\prismlauncher)') {
            Add-Failure "Absolute local path found in: $(Get-RelativePackPath $file.FullName)"
        }
    }
    catch {
        Add-Failure "Could not inspect text file: $(Get-RelativePackPath $file.FullName)"
    }
}

$modsDirectory = Join-Path $packRootFullPath 'mods'
$modMetadata = @(Get-ChildItem -LiteralPath $modsDirectory -Filter '*.pw.toml' -File)
$rawModJars = @(Get-ChildItem -LiteralPath $modsDirectory -Filter '*.jar' -File)
$approvedRawMods = @{
    'create_salvage-1.1.0+create6.0.10.jar' = 'fda9138c05586a6ee50dbea4b91f509e3a8051bdaf059ed2f227019e50b7462b4b8b2aab08a2e759e6b834061febe145dd2273c128cae9f01ac54f8fdc519093'
    'reveal-1.0.0.jar' = '8c2c1baffa60d680d09e3bfeddeb5c34c6f0a1f8ae70a7f941fb51bb66de8e539a7db855de229bbc5a3c4b79535f6b3b9d1373be3941f7c9df51dfe1596428e2'
}
if ($rawModJars.Count -ne $approvedRawMods.Count) { Add-Failure "Expected $($approvedRawMods.Count) approved raw mod JARs, found $($rawModJars.Count)." }
foreach ($rawModJar in $rawModJars) {
    if (-not $approvedRawMods.ContainsKey($rawModJar.Name)) {
        Add-Failure "Unexpected raw mod JAR: $($rawModJar.Name)"
        continue
    }
    $actualRawJarHash = (Get-FileHash -LiteralPath $rawModJar.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
    if ($actualRawJarHash -ne $approvedRawMods[$rawModJar.Name]) {
        Add-Failure "The approved raw mod JAR does not match the reviewed file: $($rawModJar.Name)"
    }
}

$mirrorAssetsPath = Join-Path $packRootFullPath 'mirror-assets'
$mirrorManifestPath = Join-Path $mirrorAssetsPath 'manifest.json'
if (-not (Test-Path -LiteralPath $mirrorManifestPath -PathType Leaf)) {
    Add-Failure 'The raw JAR mirror manifest is missing.'
}
else {
    try {
        $mirrorManifest = Get-Content -LiteralPath $mirrorManifestPath -Raw | ConvertFrom-Json
        $mirrorAssets = @($mirrorManifest.assets)
        if ($mirrorManifest.format -ne 1 -or $mirrorAssets.Count -ne $rawModJars.Count) {
            Add-Failure 'The raw JAR mirror manifest does not match the approved JAR count.'
        }
        foreach ($asset in $mirrorAssets) {
            $rawJar = $rawModJars | Where-Object { $_.Name -eq [string]$asset.name } | Select-Object -First 1
            $encodedPath = Join-Path $mirrorAssetsPath ([string]$asset.source)
            if ($null -eq $rawJar -or -not (Test-Path -LiteralPath $encodedPath -PathType Leaf)) {
                Add-Failure "The raw JAR mirror entry is incomplete: $($asset.name)"
                continue
            }
            $decoded = [Convert]::FromBase64String((Get-Content -LiteralPath $encodedPath -Raw).Trim())
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                $decodedHash = ([BitConverter]::ToString($sha256.ComputeHash($decoded))).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $sha256.Dispose()
            }
            $rawHash = (Get-FileHash -LiteralPath $rawJar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($decodedHash -ne $rawHash -or $decodedHash -ne ([string]$asset.sha256).ToLowerInvariant()) {
                Add-Failure "The raw JAR mirror checksum does not match: $($asset.name)"
            }
        }
    }
    catch {
        Add-Failure "The raw JAR mirror manifest is invalid: $($_.Exception.Message)"
    }
}
if ($modMetadata.Count -lt 1) {
    Add-Failure 'The pack contains no Modrinth mod metadata entries.'
}
$totalModCount = $modMetadata.Count + $rawModJars.Count

foreach ($metadata in $modMetadata) {
    $content = Get-Content -LiteralPath $metadata.FullName -Raw
    if ($content -notmatch '(?m)^url = "https://cdn\.modrinth\.com/' -or
        $content -notmatch '(?m)^hash-format = "sha512"$' -or
        $content -notmatch '(?m)^hash = "[0-9a-f]{128}"$' -or
        $content -notmatch '(?m)^mod-id = "[^"]+"$' -or
        $content -notmatch '(?m)^version = "[^"]+"$') {
        Add-Failure "Incomplete Modrinth metadata: $(Get-RelativePackPath $metadata.FullName)"
    }
}

$resourcepackMetadata = @(Get-ChildItem -LiteralPath (Join-Path $packRootFullPath 'resourcepacks') -Filter '*.pw.toml' -File)
if ($resourcepackMetadata.Count -ne 1) {
    Add-Failure "Expected one Default Dark Mode metadata entry, found $($resourcepackMetadata.Count)."
}
elseif ((Get-Content -LiteralPath $resourcepackMetadata[0].FullName -Raw) -notmatch 'mod-id = "6SLU7tS5"') {
    Add-Failure 'The resource pack is not pinned to Default Dark Mode on Modrinth.'
}

if (Test-Path -LiteralPath $packTomlPath -PathType Leaf) {
    $packToml = Get-Content -LiteralPath $packTomlPath -Raw
    foreach ($expected in @(
        'version = "1.1.4-ely.1"',
        'minecraft = "1.21.1"',
        'neoforge = "21.1.238"',
        'no-internal-hashes = true'
    )) {
        if (-not $packToml.Contains($expected)) { Add-Failure "pack.toml is missing: $expected" }
    }
}

if ((Test-Path -LiteralPath $packTomlPath -PathType Leaf) -and (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    $actualIndexHash = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $packToml = Get-Content -LiteralPath $packTomlPath -Raw
    $configuredHash = [regex]::Match($packToml, '(?ms)\[index\].*?hash\s*=\s*"([0-9a-f]{64})"').Groups[1].Value
    if ($configuredHash -ne $actualIndexHash) {
        Add-Failure "pack.toml index hash does not match index.toml ($configuredHash != $actualIndexHash)."
    }

    $indexContent = (Get-Content -LiteralPath $indexPath -Raw).Replace("`r`n", "`n")
    foreach ($requiredPreservePath in @(
        'options.txt',
        'config/DistantHorizons.toml',
        'config/quickskin-client.json',
        'config/voicechat/voicechat-client.properties'
    )) {
        $quotedPath = [regex]::Escape($requiredPreservePath)
        $preservePattern = '(?ms)\[\[files\]\].*?file\s*=\s*"{0}"\s*\npreserve\s*=\s*true' -f $quotedPath
        if ($indexContent -notmatch $preservePattern) {
            Add-Failure "Expected preserve=true for $requiredPreservePath."
        }
    }
}

$optionsPath = Join-Path $packRootFullPath 'options.txt'
if (-not (Test-Path -LiteralPath $optionsPath -PathType Leaf)) {
    Add-Failure 'options.txt is missing.'
}
elseif ((Get-Content -LiteralPath $optionsPath -Raw) -notmatch '(?m)^lang:ru_ru\r?$') {
    Add-Failure 'options.txt must start players with the Russian language selected.'
}
elseif ((Get-Content -LiteralPath $optionsPath -Raw) -match '(?m)^lastServer:') {
    Add-Failure 'options.txt must not contain a remembered server address.'
}

foreach ($requiredDirectory in @('config', 'defaultconfigs', 'kubejs', 'global_packs')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packRootFullPath $requiredDirectory) -PathType Container)) {
        Add-Failure "Required pack directory is missing: $requiredDirectory"
    }
}

if ($failures.Count -gt 0) {
    throw ("Pack validation failed:`n - " + ($failures -join "`n - "))
}

Write-Host "Pack validation passed: $totalModCount mods, Default Dark Mode, clean configuration and valid index hash."
