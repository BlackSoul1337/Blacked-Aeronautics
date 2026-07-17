[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JavaPath,
    [string]$InstallerPath,
    [ValidateRange(1, 3)]
    [int]$AttemptsPerSource = 2,
    [ValidateRange(15, 300)]
    [int]$DownloadTimeoutSeconds = 60,
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

$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    [Console]::OutputEncoding = $utf8
}
catch {
    # Some non-interactive hosts do not expose a configurable console.
}
$OutputEncoding = $utf8

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

function Write-ProcessOutput([string]$Text) {
    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        Write-Host $Text.TrimEnd()
    }
}

function Invoke-PackwizInstaller([string]$Java, [string]$Installer, [string]$PackUrl) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Java
    $startInfo.Arguments = (
        '-Djava.net.useSystemProxies=true -Dfile.encoding=UTF-8 ' +
        '-Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8 ' +
        '-cp "{0}" link.infra.packwiz.installer.Main --no-gui --timeout {1} "{2}"'
    ) -f $Installer, $DownloadTimeoutSeconds, $PackUrl
    $startInfo.WorkingDirectory = $ScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8

    $process = $null
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-ProcessOutput $standardOutput.Result
        Write-ProcessOutput $standardError.Result
        return $process.ExitCode
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
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
foreach ($packUrl in $PackUrls) {
    $packUri = $null
    if (-not [uri]::TryCreate($packUrl, [System.UriKind]::Absolute, [ref]$packUri) -or
        $packUri.Scheme -ne [uri]::UriSchemeHttps) {
        throw "Refusing an invalid update source: $packUrl"
    }
}

$consoleJava = Join-Path (Split-Path -Parent $java) 'java.exe'
if (Test-Path -LiteralPath $consoleJava -PathType Leaf) {
    $java = $consoleJava
}

$lastExitCode = 1
$attemptNumber = 0
$totalAttempts = $PackUrls.Count * $AttemptsPerSource
Push-Location $ScriptRoot
try {
    for ($round = 1; $round -le $AttemptsPerSource; $round++) {
        for ($index = 0; $index -lt $PackUrls.Count; $index++) {
            $packUrl = $PackUrls[$index]
            $attemptNumber++
            Write-Host "Updating Blacked Aeronautics from $packUrl"
            Write-Host "Update attempt $attemptNumber of $totalAttempts"
            try {
                Install-MirrorAssets $packUrl
                $lastExitCode = Invoke-PackwizInstaller $java $installer $packUrl
            }
            catch {
                Write-Host "Update attempt failed: $($_.Exception.Message)"
                $lastExitCode = 1
            }
            Write-Host "Update source exit code: $lastExitCode"
            if ($lastExitCode -eq 0) {
                exit 0
            }
            if ($attemptNumber -lt $totalAttempts) {
                Write-Host 'The update is incomplete. Retrying automatically.'
                Start-Sleep -Seconds 2
            }
        }
    }
}
finally {
    Pop-Location
}

Write-Host 'All Blacked Aeronautics update sources failed.'
exit $lastExitCode
