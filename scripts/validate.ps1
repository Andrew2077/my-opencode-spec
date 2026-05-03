[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
}

$repo = (Get-Item -LiteralPath $RepoRoot).FullName
$manifestPath = Join-Path $repo "sync-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing sync-manifest.json"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$errors = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$Message) {
    $script:errors.Add($Message) | Out-Null
}

function Get-RepoRelativePath([string]$Path) {
    $base = (Get-Item -LiteralPath $repo).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $full = (Get-Item -LiteralPath $Path).FullName
    $baseWithSeparator = $base + [System.IO.Path]::DirectorySeparatorChar

    if ($full.StartsWith($baseWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($full.Substring($baseWithSeparator.Length) -replace "\\", "/")
    }

    throw "Path '$full' is not under '$base'"
}

function Test-GitIgnored([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo ".git"))) {
        return $false
    }

    $null = & git -C $repo check-ignore -q -- $RelativePath 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-AllowedSecretReference {
    param(
        [string]$Value,
        [string]$RelativePath
    )

    $allowFragments = @(
        "your_",
        "your-",
        "__SET_IN_LOCAL_ENV_OR_CONFIG__",
        "placeholder",
        "example",
        "REDACTED",
        "changeme",
        "process.env.",
        "context.env.",
        "this.env.",
        "env.",
        "var.",
        "request.headers.get",
        "config.requireSecret",
        "SecretsStoreBinding"
    )

    foreach ($fragment in $allowFragments) {
        if ($Value -match [regex]::Escape($fragment)) { return $true }
    }

    if ($RelativePath -match "(^|/)(docs|\.opencode/skill)/" -and $Value -match "(?i)(API_KEY|TOKEN|SECRET|PASSWORD)") {
        return $true
    }

    return $false
}

$required = @("README.md", ".gitignore", "sync-manifest.json", "scripts/fetch-from-device.ps1", "scripts/install-to-opencode.ps1", "scripts/validate.ps1", "docs/OPENCODE_SYNC.md", "docs/OPENSPEC.md", "docs/SECURITY.md")
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $path))) {
        Add-Error "missing required file: $path"
    }
}

$deniedExact = @(
    ".opencode/.env",
    ".opencode/opencode.json",
    ".opencode/memory.db",
    ".opencode/memory.db-shm",
    ".opencode/memory.db-wal"
)
foreach ($path in $deniedExact) {
    if ((Test-Path -LiteralPath (Join-Path $repo $path)) -and -not (Test-GitIgnored -RelativePath $path)) {
        Add-Error "denied file present: $path"
    }
}

$allFiles = Get-ChildItem -LiteralPath $repo -Recurse -File -Force | Where-Object {
    if ($_.FullName -match "\\.git(\\|$)" -or $_.FullName -match "\\node_modules(\\|$)") { return $false }
    $rel = Get-RepoRelativePath $_.FullName
    return -not (Test-GitIgnored -RelativePath $rel)
}

foreach ($file in $allFiles) {
    $rel = Get-RepoRelativePath $file.FullName
    if ($rel -match "(^|/)node_modules(/|$)") { Add-Error "node_modules file present: $rel" }
    if ($rel -match "(^|/)memory\.db") { Add-Error "memory db file present: $rel" }
    if ($rel -match "(^|/)\.env($|\.)" -and $rel -notmatch "\.env\.example$") { Add-Error "env secret file present: $rel" }
    if ($rel -match "\.(bak|backup|tmp|temp|orig|old)$") { Add-Error "backup/temp file present: $rel" }
}

$binaryExtensions = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf", ".zip", ".gz", ".tar", ".exe", ".dll")
$scanFiles = $allFiles | Where-Object { $binaryExtensions -notcontains $_.Extension.ToLowerInvariant() }
$secretPatterns = @($manifest.secretPatterns)

foreach ($file in $scanFiles) {
    $rel = Get-RepoRelativePath $file.FullName
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { continue }
    foreach ($pattern in $secretPatterns) {
        $matches = [regex]::Matches($content, [string]$pattern)
        foreach ($match in $matches) {
            $value = $match.Value
            $isAllowed = Test-AllowedSecretReference -Value $value -RelativePath $rel
            if (-not $isAllowed) {
                Add-Error "possible secret in ${rel}: $($value.Substring(0, [Math]::Min(60, $value.Length)))"
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "Validation failed:" -ForegroundColor Red
    foreach ($errorItem in $errors) { Write-Host "- $errorItem" -ForegroundColor Red }
    exit 1
}

Write-Host "Validation passed: no denied files or obvious secrets found."
