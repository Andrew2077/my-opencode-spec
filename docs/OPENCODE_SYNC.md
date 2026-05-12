# OpenCode Sync Workflow

## Purpose

Use this repo as a private, portable source of truth for OpenCode customization while keeping machine-local secrets and runtime state off Git.

## Fetch from current device

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-from-device.ps1 -DryRun -IncludeConfig
powershell -ExecutionPolicy Bypass -File scripts/fetch-from-device.ps1 -IncludeConfig
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

Default source is `$HOME\.opencode`. Override it when needed:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-from-device.ps1 -Source "$HOME\.opencode" -IncludeConfig
```

## Install onto a device

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1
```

The installer copies repo `.opencode/` contents to `$HOME\.opencode` and creates a timestamped backup first unless `-NoBackup` is passed.

## Local config after install

The install script intentionally skips raw `opencode.json` and `.env`.

Create local copies:

```powershell
Copy-Item "$HOME\.opencode\.env.example" "$HOME\.opencode\.env"
Copy-Item "$HOME\.opencode\opencode.example.json" "$HOME\.opencode\opencode.json"
```

Then edit provider URLs, API keys, local model settings, and machine-specific paths.

## Safe update loop

1. Change OpenCode setup locally.
2. Fetch into repo with `fetch-from-device.ps1 -IncludeConfig`.
3. Run `validate.ps1`.
4. Review `git diff`.
5. Commit and push to the private repo.
6. Pull on other devices and run `install-to-opencode.ps1`.

## Intentional exclusions

- `.env` and any `.env.*` except `.env.example`.
- `opencode.json` with real provider keys.
- `memory.db*` and session databases.
- `node_modules/`.
- Backups, logs, temp files.

## Recovery

Installer backups are created next to the target folder:

```text
$HOME\.opencode.backup-YYYYMMDD-HHMMSS
```

To restore, move the broken `$HOME\.opencode` aside and rename the backup to `.opencode`.
