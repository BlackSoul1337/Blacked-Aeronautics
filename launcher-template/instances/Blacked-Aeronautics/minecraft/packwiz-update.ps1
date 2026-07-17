[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,
    [string]$InstallerPath,
    [string[]]$PackUrls = @(
        'https://blacksoul1337.github.io/Blacked-Aeronautics/pack.toml',
        'https://cdn.jsdelivr.net/gh/BlackSoul1337/Blacked-Aeronautics@main/pack/pack.toml'
    )
)

if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'Windows PowerShell 5.1 or newer is required to update Blacked Aeronautics.'
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptFile = [string]$MyInvocation.MyCommand.Path
if (-not [string]::IsNullOrWhiteSpace($scriptFile)) {
    $ScriptRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($scriptFile))
}
elseif (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
}
else {
    $ScriptRoot = [System.IO.Path]::GetFullPath((Get-Location).ProviderPath)
}
if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
    throw 'The pack updater could not determine its own directory.'
}
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $ScriptRoot 'packwiz-installer.jar'
}
elseif (-not [System.IO.Path]::IsPathRooted($InstallerPath)) {
    $InstallerPath = Join-Path $ScriptRoot $InstallerPath
}

function Get-HttpsText([uri]$Uri) {
    if ($Uri.Scheme -ne [uri]::UriSchemeHttps) {
        throw "Refusing a non-HTTPS update source: $Uri"
    }

    $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
    $request.Method = 'GET'
    $request.UserAgent = 'Blacked-Aeronautics-Pack-Updater/1.1.6'
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $request.Timeout = 15000
    $request.ReadWriteTimeout = 15000
    $request.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    if ($null -ne $request.Proxy) {
        $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    }

    $response = $null
    $stream = $null
    $reader = $null
    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

function Get-Sha256Hex([byte[]]$Bytes) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Install-MirrorAssets([string]$PackUrl) {
    $packUri = [uri]$PackUrl
    if ($packUri.Host -ne 'cdn.jsdelivr.net') {
        return
    }

    $manifestUri = [uri]::new($packUri, 'mirror-assets/manifest.json')
    $manifest = Get-HttpsText $manifestUri | ConvertFrom-Json
    $assets = @($manifest.assets)
    if ($manifest.format -ne 1 -or $assets.Count -eq 0 -or $assets.Count -gt 16) {
        throw 'The mirror asset manifest is invalid.'
    }

    $modsPath = Join-Path $ScriptRoot 'mods'
    [System.IO.Directory]::CreateDirectory($modsPath) | Out-Null
    foreach ($asset in $assets) {
        $name = [string]$asset.name
        $source = [string]$asset.source
        $expectedHash = ([string]$asset.sha256).ToLowerInvariant()
        if ($name -notmatch '^[A-Za-z0-9._+-]+\.jar$' -or
            $source -notmatch '^[A-Za-z0-9._+-]+\.jar\.b64$' -or
            $expectedHash -notmatch '^[0-9a-f]{64}$') {
            throw 'The mirror asset manifest contains an invalid entry.'
        }

        $target = Join-Path $modsPath $name
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $currentHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($currentHash -eq $expectedHash) {
                continue
            }
        }

        $sourceUri = [uri]::new($manifestUri, $source)
        $encoded = (Get-HttpsText $sourceUri).Trim()
        if ($encoded.Length -eq 0 -or $encoded.Length -gt 25000000) {
            throw "The mirror asset is empty or too large: $source"
        }
        try {
            $bytes = [Convert]::FromBase64String($encoded)
        }
        catch {
            throw "The mirror asset is not valid Base64: $source"
        }
        if ((Get-Sha256Hex $bytes) -ne $expectedHash) {
            throw "The mirror asset checksum does not match: $name"
        }

        $temporary = $target + '.mirror-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllBytes($temporary, $bytes)
            [System.IO.File]::Copy($temporary, $target, $true)
        }
        finally {
            if (Test-Path -LiteralPath $temporary -PathType Leaf) {
                Remove-Item -LiteralPath $temporary -Force
            }
        }
    }
}

$java = [System.IO.Path]::GetFullPath($JavaPath)
$installer = [System.IO.Path]::GetFullPath($InstallerPath)
if (-not (Test-Path -LiteralPath $java -PathType Leaf)) {
    throw "Bundled Java was not found: $java"
}
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Bundled packwiz-installer was not found: $installer"
}
if ($PackUrls.Count -eq 0) {
    throw 'No Blacked Aeronautics update sources are configured.'
}

$consoleJava = Join-Path (Split-Path -Parent $java) 'java.exe'
if (Test-Path -LiteralPath $consoleJava -PathType Leaf) {
    $java = $consoleJava
}

$lastExitCode = 1
Push-Location $ScriptRoot
try {
    for ($index = 0; $index -lt $PackUrls.Count; $index++) {
        $packUrl = $PackUrls[$index]
        Write-Host "Updating Blacked Aeronautics from $packUrl"
        try {
            Install-MirrorAssets $packUrl
        }
        catch {
            Write-Warning "The mirror support files failed validation: $($_.Exception.Message)"
            $lastExitCode = 1
            continue
        }
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $java
        $startInfo.Arguments = '-Djava.net.useSystemProxies=true -cp "{0}" link.infra.packwiz.installer.Main --no-gui --timeout 15 "{1}"' -f $installer, $packUrl
        $startInfo.WorkingDirectory = $ScriptRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = $null
        try {
            $process = [System.Diagnostics.Process]::Start($startInfo)
            $process.WaitForExit()
            $lastExitCode = $process.ExitCode
        }
        finally {
            if ($null -ne $process) {
                $process.Dispose()
            }
        }
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
