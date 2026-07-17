[CmdletBinding()]
param(
    [string]$PackRoot = (Join-Path $PSScriptRoot '..\pack')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packRootPath = [System.IO.Path]::GetFullPath($PackRoot)
$modsPath = Join-Path $packRootPath 'mods'
$mirrorPath = Join-Path $packRootPath 'mirror-assets'
if (-not (Test-Path -LiteralPath $modsPath -PathType Container)) {
    throw "Pack mods directory was not found: $modsPath"
}

$rawJars = @(Get-ChildItem -LiteralPath $modsPath -Filter '*.jar' -File | Sort-Object Name)
if ($rawJars.Count -eq 0) {
    throw 'No approved raw JARs are available for mirror generation.'
}

[System.IO.Directory]::CreateDirectory($mirrorPath) | Out-Null
$assets = foreach ($jar in $rawJars) {
    $sourceName = $jar.Name + '.b64'
    $sourcePath = Join-Path $mirrorPath $sourceName
    $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($jar.FullName))
    [System.IO.File]::WriteAllText($sourcePath, $base64, [System.Text.UTF8Encoding]::new($false))
    [ordered]@{
        name = $jar.Name
        source = $sourceName
        sha256 = (Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$expectedSources = @($assets | ForEach-Object { $_.source })
Get-ChildItem -LiteralPath $mirrorPath -Filter '*.b64' -File | Where-Object {
    $_.Name -notin $expectedSources
} | Remove-Item -Force

$manifest = [ordered]@{
    format = 1
    assets = @($assets)
} | ConvertTo-Json -Depth 4 -Compress
$manifest = $manifest.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n")
[System.IO.File]::WriteAllText(
    (Join-Path $mirrorPath 'manifest.json'),
    $manifest + "`n",
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Mirror assets refreshed: $($assets.Count)"
