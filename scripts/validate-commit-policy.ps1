[CmdletBinding()]
param(
    [string]$BaseSha,
    [string]$HeadSha = 'HEAD',
    [AllowEmptyString()]
    [string]$PullRequestTitle,
    [string]$BaseBranch,
    [string]$HeadBranch,
    [switch]$TestFixtures
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$allowedTypes = @(
    'feat', 'fix', 'docs', 'style', 'refactor', 'perf',
    'test', 'build', 'ci', 'chore', 'revert'
)
$allowedScopes = @(
    'repo', 'pack', 'launcher', 'updater',
    'installer', 'release', 'ci', 'deps'
)
$pastTenseStarts = @(
    'added', 'allowed', 'blocked', 'changed', 'closed', 'configured',
    'created', 'disabled', 'documented', 'enabled', 'fixed', 'hardened',
    'implemented', 'improved', 'merged', 'moved', 'opened', 'prepared',
    'preserved', 'refactored', 'removed', 'renamed', 'replaced',
    'reverted', 'tested', 'updated'
)

$typePattern = ($allowedTypes | ForEach-Object { [regex]::Escape($_) }) -join '|'
$scopePattern = ($allowedScopes | ForEach-Object { [regex]::Escape($_) }) -join '|'
$headerPattern = "^(?<type>$typePattern)\((?<scope>$scopePattern)\)(?<breaking>!)?: (?<subject>.+)$"

function Test-SystemMergeMessage([string]$Header) {
    return $Header -match '^Merge (pull request|branch|remote-tracking branch)\b'
}

function Get-MessageFailures(
    [string]$Message,
    [string]$Label,
    [bool]$AllowSystemMerge
) {
    $failures = New-Object System.Collections.Generic.List[string]
    $newline = [string][char]10
    $crlf = ([string][char]13) + $newline
    $normalized = $Message.Replace($crlf, $newline).TrimEnd([char]13, [char]10)
    $lines = @($normalized -split $newline, 0, 'SimpleMatch')

    if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
        $failures.Add("$Label has an empty header")
        return $failures
    }

    $header = $lines[0]
    if ($AllowSystemMerge -and (Test-SystemMergeMessage $header)) {
        return $failures
    }

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line.Length -gt 100) {
            $failures.Add("$Label line $($index + 1) exceeds 100 characters")
        }
        if ($line -match '[^\x09\x20-\x7E]') {
            $failures.Add("$Label line $($index + 1) contains non-ASCII text")
        }
    }

    $match = [regex]::Match($header, $headerPattern)
    if (-not $match.Success) {
        $failures.Add(
            "$Label must match <type>(<scope>)!?: <subject>; " +
            "allowed types: $($allowedTypes -join ', '); " +
            "allowed scopes: $($allowedScopes -join ', ')"
        )
        return $failures
    }

    $subject = $match.Groups['subject'].Value
    if ($subject -match '[.!?,;:]$') {
        $failures.Add("$Label subject ends with punctuation")
    }
    if ($subject -notmatch '^[A-Za-z0-9]') {
        $failures.Add("$Label subject must start with an English letter or digit")
    }

    $firstWord = (($subject -split '\s+', 2)[0]).ToLowerInvariant()
    if ($pastTenseStarts -contains $firstWord) {
        $failures.Add("$Label subject starts with a common past-tense verb: $firstWord")
    }

    if ($lines.Count -gt 1 -and $lines[1].Length -ne 0) {
        $failures.Add("$Label body must be separated from the header by a blank line")
    }

    return $failures
}

function Get-BranchFailures([string]$Target, [string]$Source) {
    $failures = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Target) -and
        [string]::IsNullOrWhiteSpace($Source)) {
        return $failures
    }
    if ([string]::IsNullOrWhiteSpace($Target) -or
        [string]::IsNullOrWhiteSpace($Source)) {
        $failures.Add('Both base and head branches are required for routing validation')
        return $failures
    }

    $workingBranch = '^(feature|bugfix|hotfix|docs|chore)/[a-z0-9][a-z0-9._-]*$'
    if ($Source -match '^(feature|bugfix|hotfix|docs|chore)/' -and
        $Source -notmatch $workingBranch) {
        $failures.Add("Working branch has an invalid name: $Source")
        return $failures
    }

    $allowed = switch ($Target) {
        'develop' {
            $Source -eq 'release' -or
            $Source -match '^(feature|docs|chore)/[a-z0-9][a-z0-9._-]*$' -or
            $Source -match '^dependabot/'
        }
        'release' {
            $Source -eq 'develop' -or
            $Source -eq 'main' -or
            $Source -match '^bugfix/[a-z0-9][a-z0-9._-]*$'
        }
        'main' {
            $Source -eq 'release' -or
            $Source -match '^hotfix/[a-z0-9][a-z0-9._-]*$'
        }
        default { $false }
    }

    if (-not $allowed) {
        $failures.Add("PR route is not allowed: $Source -> $Target")
    }
    return $failures
}

function Assert-NoFailures([System.Collections.IEnumerable]$Failures) {
    $items = @($Failures)
    if ($items.Count -gt 0) {
        $items | ForEach-Object { Write-Error $_ -ErrorAction Continue }
        throw "Commit policy validation failed with $($items.Count) error(s)"
    }
}

function Invoke-FixtureTests {
    $newline = [Environment]::NewLine
    $validMessages = @(
        'feat(pack): add navigation mod',
        'fix(launcher): prevent incomplete update',
        ('docs(repo): explain contribution flow' + $newline + $newline +
            'Keep each body line concise'),
        'feat(updater)!: change update manifest format'
    )
    $invalidMessages = @(
        'feat: omit required scope',
        'feat(other): use unknown scope',
        'fix(pack): добавь проверку',
        'fix(pack): add validation.',
        'fix(pack): fixed validation',
        ('docs(repo): ' + ('a' * 90))
    )

    foreach ($message in $validMessages) {
        $failures = @(Get-MessageFailures $message 'fixture' $false)
        if ($failures.Count -ne 0) {
            throw "Valid fixture failed: $message$newline$($failures -join $newline)"
        }
    }
    foreach ($message in $invalidMessages) {
        $failures = @(Get-MessageFailures $message 'fixture' $false)
        if ($failures.Count -eq 0) {
            throw "Invalid fixture passed: $message"
        }
    }

    $validRoutes = @(
        @('develop', 'feature/repository-governance'),
        @('develop', 'release'),
        @('release', 'develop'),
        @('release', 'bugfix/config-load'),
        @('release', 'main'),
        @('main', 'release'),
        @('main', 'hotfix/update-failure')
    )
    foreach ($route in $validRoutes) {
        if (@(Get-BranchFailures $route[0] $route[1]).Count -ne 0) {
            throw "Valid route failed: $($route[1]) -> $($route[0])"
        }
    }
    if (@(Get-BranchFailures 'main' 'feature/direct-production').Count -eq 0) {
        throw 'Invalid route passed: feature/direct-production -> main'
    }

    Write-Host 'Commit policy fixtures passed.'
}

if ($TestFixtures) {
    Invoke-FixtureTests
}

$allFailures = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($PullRequestTitle)) {
    foreach ($failure in @(Get-MessageFailures $PullRequestTitle 'PR title' $false)) {
        $allFailures.Add($failure)
    }
}
foreach ($failure in @(Get-BranchFailures $BaseBranch $HeadBranch)) {
    $allFailures.Add($failure)
}

if (-not [string]::IsNullOrWhiteSpace($BaseSha)) {
    git cat-file -e "$BaseSha^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "Base commit is unavailable: $BaseSha" }
    git cat-file -e "$HeadSha^{commit}"
    if ($LASTEXITCODE -ne 0) { throw "Head commit is unavailable: $HeadSha" }

    $commits = @(git rev-list --reverse "$BaseSha..$HeadSha")
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate PR commits' }
    foreach ($commit in $commits) {
        $message = git show -s --format=%B $commit
        if ($LASTEXITCODE -ne 0) { throw "Could not read commit $commit" }
        $joinedMessage = $message -join [Environment]::NewLine
        foreach ($failure in @(
            Get-MessageFailures $joinedMessage "Commit $commit" $true
        )) {
            $allFailures.Add($failure)
        }
    }
}

Assert-NoFailures $allFailures
if (-not $TestFixtures -or
    -not [string]::IsNullOrWhiteSpace($BaseSha) -or
    -not [string]::IsNullOrWhiteSpace($PullRequestTitle)) {
    Write-Host 'Commit policy validation passed.'
}
