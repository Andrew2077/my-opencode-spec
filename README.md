# my-opencode-spec

Private sync repo for Andrew's OpenCode setup: agents, commands, skills, tools, plugins, context files, DCP prompts, and docs.

This repo is designed to be **private**. It still treats secrets as forbidden: private Git is not secret storage.

## What this repo syncs

- `.opencode/agent/` — custom agent prompts.
- `.opencode/command/` — slash command prompts.
- `.opencode/skill/` — reusable OpenCode skills and references.
- `.opencode/tool/` — custom tools such as Context7 and grep.app search.
- `.opencode/plugin/` — TypeScript plugins for memory, sessions, prompt leverage, skill MCP, RTK, and Copilot integration.
- `.opencode/context/` and `.opencode/dcp-prompts/` — injected context and context-management prompts.
- Safe config templates such as `.env.example`, `dcp.jsonc`, `tui.json`, `opencodex-fast.jsonc`, package manifests, and `opencode.example.json`.

## What this repo never syncs

- `.env` files.
- Raw `.opencode/opencode.json` with real provider keys.
- OpenCode runtime databases: `memory.db*`, session DBs.
- `node_modules/`.
- Backups, temp files, logs, and generated local state.

## Fetch current machine setup into repo

Dry run first:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-from-device.ps1 -DryRun -IncludeConfig
```

Apply:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fetch-from-device.ps1 -IncludeConfig
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

`-IncludeConfig` creates `.opencode/opencode.example.json` with sensitive keys redacted. It does not commit raw `opencode.json`.

## Install setup onto another machine

Dry run first:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1 -DryRun
```

Apply with automatic backup:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1
```

Then create local-only secrets/config:

```powershell
Copy-Item "$HOME\.opencode\.env.example" "$HOME\.opencode\.env"
Copy-Item "$HOME\.opencode\opencode.example.json" "$HOME\.opencode\opencode.json"
```

Edit those local files manually. Do not commit them.

## Validation

Run before every commit/push:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
git status --short
git diff --cached
```

## Create private GitHub repo

After validating and reviewing staged files:

```bash
git init
git add README.md .gitignore sync-manifest.json scripts docs .opencode
git commit -m "chore: bootstrap opencode setup sync repo"
gh repo create OWNER/my-opencode-spec --private --source . --remote origin
git push -u origin main
```

Do not run `gh repo create` or `git push` until you confirm the owner/name and private visibility.

## OpenSpec

See [`docs/OPENSPEC.md`](docs/OPENSPEC.md) for installing OpenSpec and using it with this OpenCode setup.
