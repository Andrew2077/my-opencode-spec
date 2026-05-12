[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Source = (Join-Path $HOME ".opencode"),
    [string]$RepoRoot,
    [switch]$DryRun,
    [switch]$IncludeConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $item.FullName
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
    param(
        [string]$RelativePath,
        [array]$ExcludePatterns
    )

    $normalized = ($RelativePath -replace "\\", "/").TrimStart("/")
    foreach ($pattern in $ExcludePatterns) {
        $p = ($pattern -replace "\\", "/").TrimStart("/")
        if ($normalized -eq $p) { return $true }
        if ($normalized -like $p) { return $true }
        if ((Split-Path -Leaf $normalized) -like $p) { return $true }
        if ($normalized -match "(^|/)node_modules(/|$)") { return $true }
    }
    return $false
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($DryRun) {
            Write-Host "DRY create directory $Path"
        } else {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
        }
    }
}

function Copy-FileSafe {
    param(
        [string]$From,
        [string]$To
    )

    Ensure-Directory (Split-Path -Parent $To)
    if ($DryRun) {
        Write-Host "DRY copy $From -> $To"
    } else {
        Copy-Item -LiteralPath $From -Destination $To -Force
        Write-Host "copied $From -> $To"
    }
}

function Get-IncludedFiles {
    param(
        [string]$RootPath,
        [array]$ExcludePatterns
    )

    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $RootPath))

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        Get-ChildItem -LiteralPath $current.FullName -Force | ForEach-Object {
            $relative = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $_.FullName
            if (Test-ExcludedPath -RelativePath $relative -ExcludePatterns $ExcludePatterns) {
                Write-Host "skip excluded $relative"
                return
            }

            if ($_.PSIsContainer) {
                $stack.Push($_)
            } else {
                $_
            }
        }
    }
}

function Redact-JsonObject {
    param(
        [Parameter(Mandatory)]$Value,
        [string[]]$RedactKeys,
        [string]$Redaction
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ($RedactKeys -contains [string]$key) {
                $out[$key] = $Redaction
            } else {
                $out[$key] = Redact-JsonObject -Value $Value[$key] -RedactKeys $RedactKeys -Redaction $Redaction
            }
        }
        return $out
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($prop in $Value.PSObject.Properties) {
            if ($RedactKeys -contains $prop.Name) {
                $out[$prop.Name] = $Redaction
            } else {
                $out[$prop.Name] = Redact-JsonObject -Value $prop.Value -RedactKeys $RedactKeys -Redaction $Redaction
            }
        }
        return $out
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @()
        foreach ($item in $Value) {
            $items += ,(Redact-JsonObject -Value $item -RedactKeys $RedactKeys -Redaction $Redaction)
        }
        return $items
    }

    return $Value
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
}

$repo = Resolve-FullPath $RepoRoot
$sourceRoot = Resolve-FullPath $Source
$manifestPath = Join-Path $repo "sync-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing manifest: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$destinationRoot = Join-Path $repo $manifest.destinationRoot
Ensure-Directory $destinationRoot

Write-Host "Source: $sourceRoot"
Write-Host "Destination: $destinationRoot"
if ($DryRun) { Write-Host "Mode: dry run" }

foreach ($entry in $manifest.include) {
    $sourcePath = Join-Path $sourceRoot $entry
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-Warning "skip missing $entry"
        continue
    }

    $item = Get-Item -LiteralPath $sourcePath
    if ($item.PSIsContainer) {
        Get-IncludedFiles -RootPath $sourcePath -ExcludePatterns $manifest.exclude | ForEach-Object {
            $relativeToSource = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $_.FullName
            $to = Join-Path $destinationRoot $relativeToSource
            Copy-FileSafe -From $_.FullName -To $to
        }
    } else {
        if (Test-ExcludedPath -RelativePath $entry -ExcludePatterns $manifest.exclude) {
            Write-Host "skip excluded $entry"
            continue
        }
        $to = Join-Path $destinationRoot $entry
        Copy-FileSafe -From $sourcePath -To $to
    }
}

foreach ($rule in $manifest.sanitizeJson) {
    if (-not $IncludeConfig) {
        Write-Host "skip sanitized config $($rule.source) (pass -IncludeConfig to generate $($rule.destination))"
        continue
    }

    $sourceJson = Join-Path $sourceRoot $rule.source
    if (-not (Test-Path -LiteralPath $sourceJson)) {
        Write-Warning "skip missing sanitized config $($rule.source)"
        continue
    }

    $targetJson = Join-Path $destinationRoot $rule.destination
    $json = Get-Content -LiteralPath $sourceJson -Raw | ConvertFrom-Json
    $redacted = Redact-JsonObject -Value $json -RedactKeys ([string[]]$rule.redactKeys) -Redaction $rule.redaction
    Ensure-Directory (Split-Path -Parent $targetJson)
    if ($DryRun) {
        Write-Host "DRY sanitize $sourceJson -> $targetJson"
    } else {
        $serialized = $redacted | ConvertTo-Json -Depth 100
        if ($rule.PSObject.Properties.Name -contains 'stringReplacements' -and $null -ne $rule.stringReplacements) {
            foreach ($replacement in $rule.stringReplacements) {
                $pattern = [string]$replacement.pattern
                $replace = [string]$replacement.replacement
                if (-not [string]::IsNullOrEmpty($pattern)) {
                    $before = $serialized
                    $serialized = [regex]::Replace($serialized, $pattern, $replace)
                    if ($before -ne $serialized) {
                        Write-Host "applied sanitize rule: $($replacement.description)"
                    }
                }
            }
        }
        $serialized | Set-Content -LiteralPath $targetJson -Encoding UTF8
        Write-Host "sanitized $sourceJson -> $targetJson"
    }
}

Write-Host "Fetch finished. Run scripts/validate.ps1 before committing."
