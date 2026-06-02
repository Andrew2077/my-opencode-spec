<#
.SYNOPSIS
  Fetch latest versions of all tools tracked by this OpenCode setup repo.

.DESCRIPTION
  Updates GSD (get-shit-done-cc), OpenSpec (@fission-ai/openspec), SocratiCode,
  StealthHumanizer, and OpenCode itself. Also refreshes the repo's .opencode/ assets from the
  live installation and runs validation.

  This script is idempotent and safe to run repeatedly.

.PARAMETER DryRun
  Show what would be updated without making changes.

.PARAMETER SkipNpm
  Skip npm global package updates.

.PARAMETER SkipSync
  Skip syncing live .opencode/ back into the repo.

.PARAMETER SkipValidation
  Skip running validate.ps1 after updates.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/update-tools.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/update-tools.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipNpm,
    [switch]$SkipSync,
    [switch]$SkipValidation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$LiveRoot = Join-Path $env:USERPROFILE ".opencode"
$StealthHumanizerRoot = Join-Path $env:USERPROFILE "tools\StealthHumanizer"
$StealthHumanizerPatch = Join-Path $RepoRoot "patches\stealthhumanizer-cpa.patch"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$Icon, [string]$Message) {
    Write-Host ""
    Write-Host "[$Icon] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Write-Skip([string]$Message) {
    Write-Host "    SKIP: $Message" -ForegroundColor Yellow
}

function Write-Warn([string]$Message) {
    Write-Host "    WARN: $Message" -ForegroundColor Yellow
}

function Get-NpmGlobalVersion([string]$Package) {
    try {
        $out = & npm list -g $Package --depth=0 --json 2>$null | ConvertFrom-Json
        if ($out.dependencies.$Package.version) {
            return $out.dependencies.$Package.version
        }
    } catch {}
    return $null
}

function Get-NpmRegistryVersion([string]$Package) {
    try {
        $out = & npm view $Package version 2>$null
        return $out.Trim()
    } catch {}
    return $null
}

# ── Tool definitions ─────────────────────────────────────────────────────────

$Tools = @(
    @{
        Name = "GSD (get-shit-done-cc)"
        Package = "get-shit-done-cc"
        UpdateCmd = "npx get-shit-done-cc@latest --opencode --global --non-interactive"
        IsNpx = $true
    },
    @{
        Name = "OpenSpec"
        Package = "@fission-ai/openspec"
        UpdateCmd = "npm install -g @fission-ai/openspec@latest"
        IsNpx = $false
    },
    @{
        Name = "SocratiCode"
        Package = "socraticode"
        UpdateCmd = $null  # MCP server, auto-updates via npx -y
        IsNpx = $true
    },
    @{
        Name = "StealthHumanizer"
        Package = "github:rudra496/StealthHumanizer"
        UpdateCmd = $null  # GitHub clone, updated below
        IsNpx = $true
    }
)

# ── Pre-flight checks ───────────────────────────────────────────────────────

Write-Step "1" "Pre-flight checks"

$nodeVersion = & node --version 2>$null
if (-not $nodeVersion) {
    throw "Node.js not found in PATH. Install Node.js 20.19.0+ first."
}
Write-Ok "Node.js $nodeVersion"

$npmVersion = & npm --version 2>$null
Write-Ok "npm $npmVersion"

if (-not (Test-Path -LiteralPath $LiveRoot)) {
    Write-Warn "Live OpenCode directory not found at $LiveRoot"
}

# ── Check and update npm packages ───────────────────────────────────────────

if ($SkipNpm) {
    Write-Step "2" "Skipping npm updates (-SkipNpm)"
} else {
    Write-Step "2" "Checking tool versions"

    foreach ($tool in $Tools) {
        $name = $tool.Name
        $pkg = $tool.Package

        $current = Get-NpmGlobalVersion $pkg
        $latest = Get-NpmRegistryVersion $pkg

        if ($tool.IsNpx -and -not $current) {
            # npx tools may not be globally installed
            if ($latest) {
                Write-Ok "$name latest: $latest (runs via npx, not globally installed)"
            } else {
                Write-Warn "${name}: could not check registry version"
            }
            continue
        }

        if (-not $current) {
            Write-Warn "${name}: not installed globally"
            if ($DryRun) {
                Write-Host "    DRY RUN: would run: $($tool.UpdateCmd)" -ForegroundColor Magenta
            } elseif ($tool.UpdateCmd) {
                Write-Host "    Installing $name..." -ForegroundColor White
                Invoke-Expression $tool.UpdateCmd
                Write-Ok "$name installed"
            }
            continue
        }

        if ($latest -and ($current -ne $latest)) {
            Write-Host "    $name $current -> $latest" -ForegroundColor White
            if ($DryRun) {
                Write-Host "    DRY RUN: would run: $($tool.UpdateCmd)" -ForegroundColor Magenta
            } elseif ($tool.UpdateCmd) {
                Write-Host "    Updating $name..." -ForegroundColor White
                Invoke-Expression $tool.UpdateCmd
                Write-Ok "$name updated to $latest"
            }
        } else {
            Write-Ok "$name $current (up to date)"
        }
    }

    # OpenCode itself
    $opencodeVersion = $null
    try { $opencodeVersion = & opencode --version 2>$null } catch {}
    if ($opencodeVersion) {
        Write-Ok "OpenCode $opencodeVersion"
    } else {
        Write-Warn "OpenCode not found in PATH (install manually if needed)"
    }

    Write-Step "2b" "Checking StealthHumanizer local clone"
    if ($DryRun) {
        if (Test-Path -LiteralPath (Join-Path $StealthHumanizerRoot ".git")) {
            $stealthStatus = & git -C $StealthHumanizerRoot status --porcelain 2>$null
            if ($stealthStatus) {
                Write-Host "    DRY RUN: would reverse CPA patch if already applied, pull, then reapply patch" -ForegroundColor Magenta
            } else {
                Write-Host "    DRY RUN: would run: git -C $StealthHumanizerRoot pull --ff-only" -ForegroundColor Magenta
            }
        } else {
            Write-Host "    DRY RUN: would clone https://github.com/rudra496/StealthHumanizer -> $StealthHumanizerRoot" -ForegroundColor Magenta
        }
        Write-Host "    DRY RUN: would apply CPA patch from $StealthHumanizerPatch when needed" -ForegroundColor Magenta
        Write-Host "    DRY RUN: would run: npm --prefix $StealthHumanizerRoot ci" -ForegroundColor Magenta
        Write-Host "    DRY RUN: would run: npm --prefix $StealthHumanizerRoot run cli:build" -ForegroundColor Magenta
    } else {
        $stealthParent = Split-Path -Parent $StealthHumanizerRoot
        if (-not (Test-Path -LiteralPath $stealthParent)) {
            New-Item -ItemType Directory -Path $stealthParent -Force | Out-Null
        }

        if (Test-Path -LiteralPath (Join-Path $StealthHumanizerRoot ".git")) {
            $stealthStatus = & git -C $StealthHumanizerRoot status --porcelain 2>$null
            if ($stealthStatus) {
                if (Test-Path -LiteralPath $StealthHumanizerPatch) {
                    & git -C $StealthHumanizerRoot apply --unidiff-zero --reverse --check $StealthHumanizerPatch 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        & git -C $StealthHumanizerRoot apply --unidiff-zero --reverse $StealthHumanizerPatch
                        Write-Ok "Temporarily reversed StealthHumanizer CPA patch before pull"
                        & git -C $StealthHumanizerRoot pull --ff-only
                        Write-Ok "StealthHumanizer clone updated"
                    } else {
                        Write-Warn "StealthHumanizer clone has unrelated local changes; skipping pull"
                    }
                } else {
                    Write-Warn "StealthHumanizer clone has local changes and patch is missing; skipping pull"
                }
            } else {
                & git -C $StealthHumanizerRoot pull --ff-only
                Write-Ok "StealthHumanizer clone updated"
            }
        } else {
            & git clone https://github.com/rudra496/StealthHumanizer $StealthHumanizerRoot
            Write-Ok "StealthHumanizer cloned"
        }

        if (Test-Path -LiteralPath $StealthHumanizerPatch) {
            & git -C $StealthHumanizerRoot apply --unidiff-zero --check $StealthHumanizerPatch 2>$null
            if ($LASTEXITCODE -eq 0) {
                & git -C $StealthHumanizerRoot apply --unidiff-zero $StealthHumanizerPatch
                Write-Ok "Applied StealthHumanizer CPA patch"
            } else {
                & git -C $StealthHumanizerRoot apply --unidiff-zero --reverse --check $StealthHumanizerPatch 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Ok "StealthHumanizer CPA patch already applied"
                } else {
                    Write-Warn "StealthHumanizer CPA patch did not apply cleanly; inspect $StealthHumanizerPatch"
                }
            }
        } else {
            Write-Warn "StealthHumanizer CPA patch not found at $StealthHumanizerPatch"
        }

        & npm --prefix $StealthHumanizerRoot ci
        & npm --prefix $StealthHumanizerRoot run cli:build
        Write-Ok "StealthHumanizer CLI built"
    }
}

# ── GSD re-install (adopts latest commands/agents/workflows) ─────────────────

Write-Step "3" "Re-running GSD installer to adopt latest updates"

if ($DryRun) {
    Write-Host "    DRY RUN: would run: npx get-shit-done-cc@latest --opencode --global --non-interactive" -ForegroundColor Magenta
} else {
    try {
        & npx get-shit-done-cc@latest --opencode --global --non-interactive 2>&1 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
        Write-Ok "GSD installer completed"
    } catch {
        Write-Warn "GSD installer failed: $_"
        Write-Host "    You may need to run it manually: npx get-shit-done-cc@latest" -ForegroundColor Yellow
    }
}

# ── Sync live .opencode/ back into repo ──────────────────────────────────────

if ($SkipSync) {
    Write-Step "4" "Skipping repo sync (-SkipSync)"
} else {
    Write-Step "4" "Syncing live .opencode/ assets into repo"

    $repoOpencode = Join-Path $RepoRoot ".opencode"
    $manifestPath = Join-Path $RepoRoot "sync-manifest.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    # Sync included directories
    foreach ($item in $manifest.include) {
        $livePath = Join-Path $LiveRoot $item
        $repoPath = Join-Path $repoOpencode $item

        if (Test-Path -LiteralPath $livePath -PathType Container) {
            if ($DryRun) {
                Write-Host "    DRY RUN: would sync directory $item" -ForegroundColor Magenta
            } else {
                # Ensure destination exists
                if (-not (Test-Path -LiteralPath $repoPath)) {
                    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
                }
                # Copy files, preserving structure
                $files = Get-ChildItem -LiteralPath $livePath -Recurse -File -Force -ErrorAction SilentlyContinue
                foreach ($file in $files) {
                    $relFile = $file.FullName.Substring($livePath.Length)
                    $destFile = Join-Path $repoPath $relFile
                    $destDir = Split-Path $destFile -Parent
                    if (-not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force
                }
                Write-Ok "Synced directory: $item"
            }
        } elseif (Test-Path -LiteralPath $livePath -PathType Leaf) {
            if ($DryRun) {
                Write-Host "    DRY RUN: would sync file $item" -ForegroundColor Magenta
            } else {
                Copy-Item -LiteralPath $livePath -Destination $repoPath -Force
                Write-Ok "Synced file: $item"
            }
        } else {
            Write-Skip "Not found in live install: $item"
        }
    }

    # Sanitize config
    foreach ($sanitize in $manifest.sanitizeJson) {
        $sourceFile = Join-Path $LiveRoot $sanitize.source
        $destFile = Join-Path $repoOpencode $sanitize.destination

        if (Test-Path -LiteralPath $sourceFile) {
            if ($DryRun) {
                Write-Host "    DRY RUN: would sanitize $($sanitize.source) -> $($sanitize.destination)" -ForegroundColor Magenta
            } else {
                $json = Get-Content -LiteralPath $sourceFile -Raw | ConvertFrom-Json
                $redactKeys = @($sanitize.redactKeys)
                $redaction = $sanitize.redaction

                # Deep redact
                function Redact-JsonObject($obj, [string[]]$keys, [string]$replacement) {
                    if ($null -eq $obj) { return }
                    if ($obj -is [System.Management.Automation.PSCustomObject]) {
                        foreach ($prop in $obj.PSObject.Properties) {
                            if ($keys -contains $prop.Name -and $prop.Value -is [string]) {
                                $prop.Value = $replacement
                            } elseif ($prop.Value -is [System.Management.Automation.PSCustomObject] -or $prop.Value -is [System.Collections.IEnumerable]) {
                                Redact-JsonObject $prop.Value $keys $replacement
                            }
                        }
                    } elseif ($obj -is [System.Collections.IEnumerable]) {
                        foreach ($item in $obj) {
                            Redact-JsonObject $item $keys $replacement
                        }
                    }
                }

                Redact-JsonObject $json $redactKeys $redaction
                $serialized = $json | ConvertTo-Json -Depth 20
                if ($sanitize.PSObject.Properties.Name -contains 'stringReplacements' -and $null -ne $sanitize.stringReplacements) {
                    foreach ($replacement in $sanitize.stringReplacements) {
                        $pattern = [string]$replacement.pattern
                        $replace = [string]$replacement.replacement
                        if (-not [string]::IsNullOrEmpty($pattern)) {
                            $before = $serialized
                            $serialized = [regex]::Replace($serialized, $pattern, $replace)
                            if ($before -ne $serialized) {
                                Write-Ok "applied sanitize rule: $($replacement.description)"
                            }
                        }
                    }
                }
                $serialized | Set-Content -LiteralPath $destFile -Encoding UTF8
                Write-Ok "Sanitized: $($sanitize.source) -> $($sanitize.destination)"
            }
        } else {
            Write-Skip "Live config not found: $($sanitize.source)"
        }
    }
}

# ── Validation ───────────────────────────────────────────────────────────────

if ($SkipValidation) {
    Write-Step "5" "Skipping validation (-SkipValidation)"
} else {
    Write-Step "5" "Running validation"

    if ($DryRun) {
        Write-Host "    DRY RUN: would run validate.ps1" -ForegroundColor Magenta
    } else {
        try {
            & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "validate.ps1") -RepoRoot $RepoRoot
            Write-Ok "Validation passed"
        } catch {
            Write-Warn "Validation failed: $_"
        }
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Step "Done" "Update complete"

if ($DryRun) {
    Write-Host ""
    Write-Host "This was a dry run. No changes were made." -ForegroundColor Yellow
    Write-Host "Run without -DryRun to apply updates." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Review changes: git diff" -ForegroundColor DarkGray
Write-Host "  2. Stage and commit: git add <files> && git commit -m 'chore: update tools'" -ForegroundColor DarkGray
Write-Host "  3. Push: git push" -ForegroundColor DarkGray
