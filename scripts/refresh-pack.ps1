[CmdletBinding()]
param(
    [string]$PackwizPath = (Join-Path $PSScriptRoot '..\.tools\packwiz\packwiz.exe'),
    [string]$PackRoot = (Join-Path $PSScriptRoot '..\pack')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $encoding)
}

function Test-PreservedPath([string]$Path) {
    $normalized = $Path.Replace('\', '/')
    if ($normalized -eq 'options.txt') { return $true }
    if ($normalized -match '^config/xaero/') { return $true }
    if ($normalized -eq 'config/quickskin-client.json') { return $true }
    if ($normalized -match '^config/voicechat/(voicechat-client|voicechat-volumes|category-volumes)\.properties$') { return $true }
    return $false
}

$packwizFullPath = [System.IO.Path]::GetFullPath($PackwizPath)
$packRootFullPath = [System.IO.Path]::GetFullPath($PackRoot)
if (-not (Test-Path -LiteralPath $packwizFullPath -PathType Leaf)) {
    throw "packwiz executable was not found: $packwizFullPath"
}
if (-not (Test-Path -LiteralPath (Join-Path $packRootFullPath 'pack.toml') -PathType Leaf)) {
    throw "pack.toml was not found in: $packRootFullPath"
}

Push-Location $packRootFullPath
try {
    & $packwizFullPath refresh --build
    if ($LASTEXITCODE -ne 0) {
        throw "packwiz refresh --build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

$indexPath = Join-Path $packRootFullPath 'index.toml'
$indexContent = Get-Content -LiteralPath $indexPath -Raw
$blocks = [regex]::Split($indexContent.Replace("`r`n", "`n"), '(?m)(?=^\[\[files\]\]\s*$)')
$rewrittenBlocks = New-Object System.Collections.Generic.List[string]

foreach ($block in $blocks) {
    if ($block -notmatch '(?m)^\[\[files\]\]\s*$') {
        $rewrittenBlocks.Add($block.TrimEnd("`n"))
        continue
    }

    $fileMatch = [regex]::Match($block, '(?m)^file\s*=\s*"([^"]+)"\s*$')
    if (-not $fileMatch.Success) {
        throw "Malformed file block in index.toml:`n$block"
    }

    $preserve = Test-PreservedPath $fileMatch.Groups[1].Value
    $newLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($block -split "`n")) {
        if ($line -match '^preserve\s*=') {
            continue
        }
        $newLines.Add($line)
        if ($preserve -and $line -match '^file\s*=') {
            $newLines.Add('preserve = true')
        }
    }
    $rewrittenBlocks.Add(($newLines -join "`n").TrimEnd("`n"))
}

Write-Utf8NoBom $indexPath (($rewrittenBlocks -join "`n`n") + "`n")

$indexHash = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash.ToLowerInvariant()
$packTomlPath = Join-Path $packRootFullPath 'pack.toml'
$packToml = (Get-Content -LiteralPath $packTomlPath -Raw).Replace("`r`n", "`n")
$indexHashPattern = '(?ms)(\[index\]\s*\nfile\s*=\s*"index\.toml"\s*\nhash-format\s*=\s*"sha256"\s*\nhash\s*=\s*")[0-9a-fA-F]*(")'
if (-not [regex]::IsMatch($packToml, $indexHashPattern)) {
    throw 'Could not update the index hash in pack.toml.'
}
$packToml = [regex]::Replace(
    $packToml,
    $indexHashPattern,
    { param($match) $match.Groups[1].Value + $indexHash + $match.Groups[2].Value },
    1
)
Write-Utf8NoBom $packTomlPath $packToml

& (Join-Path $PSScriptRoot 'validate-pack.ps1') -PackRoot $packRootFullPath
