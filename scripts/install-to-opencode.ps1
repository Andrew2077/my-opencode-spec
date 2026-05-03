[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot,
    [string]$Target = (Join-Path $HOME ".opencode"),
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$InstallExampleConfigAsLocal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($DryRun) {
            Write-Host "DRY create directory $Path"
        } else {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = (Get-Item -LiteralPath $BasePath).FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $path = (Get-Item -LiteralPath $FullPath).FullName
    $baseWithSeparator = $base + [System.IO.Path]::DirectorySeparatorChar

    if ($path.StartsWith($baseWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($baseWithSeparator.Length)
    }

    throw "Path '$path' is not under '$base'"
}

function Test-ExcludedPath {
    param([string]$RelativePath)
    $normalized = ($RelativePath -replace "\\", "/").TrimStart("/")
    if ($normalized -match "(^|/)node_modules(/|$)") { return $true }
    if ($normalized -match "(^|/)memory\.db") { return $true }
    if ($normalized -match "(^|/)\.env($|\.)" -and $normalized -notmatch "\.env\.example$") { return $true }
    if ($normalized -eq "opencode.json") { return $true }
    if ($normalized -match "\.(bak|backup|tmp|temp|log|orig|old)$") { return $true }
    return $false
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
}

$repo = (Get-Item -LiteralPath $RepoRoot).FullName
$source = Join-Path $repo ".opencode"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing repo .opencode directory. Run scripts/fetch-from-device.ps1 first."
}

$targetRoot = $Target
Write-Host "Source: $source"
Write-Host "Target: $targetRoot"
if ($DryRun) { Write-Host "Mode: dry run" }

if ((Test-Path -LiteralPath $targetRoot) -and -not $NoBackup) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$targetRoot.backup-$timestamp"
    if ($DryRun) {
        Write-Host "DRY backup $targetRoot -> $backup"
    } else {
        Copy-Item -LiteralPath $targetRoot -Destination $backup -Recurse -Force
        Write-Host "backup created $backup"
    }
}

Ensure-Directory $targetRoot

Get-ChildItem -LiteralPath $source -Recurse -File -Force | ForEach-Object {
    $relative = Get-RelativePathCompat -BasePath $source -FullPath $_.FullName
    if (Test-ExcludedPath -RelativePath $relative) {
        Write-Host "skip protected $relative"
        return
    }

    if ($relative -eq "opencode.example.json") {
        if (-not $InstallExampleConfigAsLocal) {
            Write-Host "skip example config $relative (pass -InstallExampleConfigAsLocal to copy as opencode.json)"
            return
        }
        $destination = Join-Path $targetRoot "opencode.json"
    } else {
        $destination = Join-Path $targetRoot $relative
    }

    Ensure-Directory (Split-Path -Parent $destination)
    if ($DryRun) {
        Write-Host "DRY copy $($_.FullName) -> $destination"
    } else {
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        Write-Host "copied $relative"
    }
}

Write-Host "Install finished. Keep local .env and real opencode.json private."
