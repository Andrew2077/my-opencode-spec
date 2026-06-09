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

## LLM installation instructions

Use this section when an LLM or coding agent is asked to install this repo onto a new machine.

### Operating rules for agents

1. Treat this repository as private, but do not treat it as secret storage.
2. Never print, commit, copy into chat, or overwrite real secrets from `.env` or `.opencode/opencode.json`.
3. Do not use `git add .`; stage only the specific files you intentionally changed.
4. Do not overwrite a target machine's real `$HOME/.opencode/opencode.json` unless the user explicitly asks. Prefer copying safe assets and merging only required config keys.
5. Create or preserve a backup before changing `$HOME/.opencode`.
6. Run validation before any commit or completion claim.

### Windows install flow

Run from a fresh clone of this repo:

```powershell
git status --short --branch
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File scripts/install-to-opencode.ps1
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
```

After installation, create local-only files if they do not already exist:

```powershell
if (-not (Test-Path "$HOME\.opencode\.env")) {
  Copy-Item "$HOME\.opencode\.env.example" "$HOME\.opencode\.env"
}

if (-not (Test-Path "$HOME\.opencode\opencode.json")) {
  Copy-Item "$HOME\.opencode\opencode.example.json" "$HOME\.opencode\opencode.json"
}
```

The user must edit those local files with real provider keys. Do not invent keys.

For 9Router, fetch model IDs from the live OpenAI-compatible `/v1/models` endpoint before adding or refreshing config. Keep the real endpoint and key only in local config/env; commit only placeholders.

### Linux or VPS install flow

The PowerShell install script is the source of truth on Windows. On Linux/VPS hosts without PowerShell, mirror its behavior with shell commands:

```bash
set -eu
repo="$HOME/my-opencode-spec"
src="$repo/.opencode"
dst="$HOME/.opencode"
stamp="$(date +%Y%m%d-%H%M%S)"

test -d "$src"
mkdir -p "$dst"
cp -a "$dst" "$HOME/.opencode.backup-$stamp"

rsync -a \
  --exclude opencode.json \
  --exclude opencode.example.json \
  --exclude .env \
  --exclude memory.db \
  --exclude memory.db-shm \
  --exclude memory.db-wal \
  --exclude node_modules \
  --exclude '*.bak' \
  --exclude '*.backup' \
  --exclude '*.tmp' \
  --exclude '*.temp' \
  --exclude '*.log' \
  --exclude '*.orig' \
  --exclude '*.old' \
  "$src/" "$dst/"
```

If SocratiCode support is needed, merge only these keys into the existing real config:

```bash
node <<'NODE'
const fs = require('fs');
const path = `${process.env.HOME}/.opencode/opencode.json`;
const stamp = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);
let config = {};

if (fs.existsSync(path)) {
  fs.copyFileSync(path, `${path}.pre-socraticode-${stamp}.bak`);
  config = JSON.parse(fs.readFileSync(path, 'utf8'));
}

config.agent = config.agent || {};
config.agent['socraticode-explorer'] = {
  model: '9router/ag/gemini-3-flash-agent',
  mode: 'all',
};

config.mcp = config.mcp || {};
config.mcp.socraticode = {
  type: 'local',
  command: ['npx', '-y', 'socraticode'],
  enabled: true,
};

fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
console.log('socraticode config merged');
NODE
```

If StealthHumanizer support is needed, install the local clone and merge only the agent key into the existing real config:

```bash
set -eu
mkdir -p "$HOME/tools"
if [ ! -d "$HOME/tools/StealthHumanizer/.git" ]; then
  git clone https://github.com/rudra496/StealthHumanizer "$HOME/tools/StealthHumanizer"
fi
npm --prefix "$HOME/tools/StealthHumanizer" ci
npm --prefix "$HOME/tools/StealthHumanizer" run cli:build

node <<'NODE'
const fs = require('fs');
const path = `${process.env.HOME}/.opencode/opencode.json`;
const stamp = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14);
let config = {};

if (fs.existsSync(path)) {
  fs.copyFileSync(path, `${path}.pre-stealthhumanizer-${stamp}.bak`);
  config = JSON.parse(fs.readFileSync(path, 'utf8'));
}

config.agent = config.agent || {};
config.agent.stealthhumanizer = {
  model: '9router/ag/gemini-3-flash-agent',
  mode: 'all',
};

fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
console.log('stealthhumanizer config merged');
NODE
```

### OpenSpec install flow

Install OpenSpec only when Node.js is `20.19.0` or newer:

```bash
node --version
npm install -g @fission-ai/openspec@latest
openspec --version
```

Use the scoped package `@fission-ai/openspec`. Do not install the stale unscoped `openspec` package or nonexistent `@openspec/cli` package.

### Required verification

Before reporting completion, run the relevant checks and quote the exact output:

```bash
opencode --version
openspec --version
node -e "const c=require(process.env.HOME + '/.opencode/opencode.json'); if ((c.mcp?.socraticode?.command || []).join(' ') !== 'npx -y socraticode') process.exit(1); if (!c.agent?.['socraticode-explorer']) process.exit(2); console.log('socraticode config ok')"
test -f "$HOME/.opencode/agent/socraticode-explorer.md"
npm view socraticode version engines --json
npm --prefix "$HOME/tools/StealthHumanizer" run cli -- providers
test -f "$HOME/.opencode/agent/stealthhumanizer.md"
```

For this repo before committing:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
git status --short --branch
git diff --check
```

Expected safety outcome: raw `.opencode/opencode.json`, `.env`, `memory.db*`, `node_modules/`, backups, logs, and temp files stay untracked.

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

This setup also includes an `openspec-engineer` agent for spec-first API review. Use it when you need contract validation, OpenSpec artifact checks, or implementation/spec drift review. It uses the OpenSpec CLI and generated project assets; OpenSpec is installed per machine/project with `npm install -g @fission-ai/openspec@latest` and `openspec init --tools opencode`.

## StealthHumanizer

This setup includes a `stealthhumanizer` agent for ethical writing revision and AI-signal analysis using the StealthHumanizer CLI.

StealthHumanizer is installed from GitHub because the `stealthhumanizer` package is not published on npm:

```powershell
git clone https://github.com/rudra496/StealthHumanizer "$HOME\tools\StealthHumanizer"
npm --prefix "$HOME\tools\StealthHumanizer" ci
npm --prefix "$HOME\tools\StealthHumanizer" run cli:build
npm --prefix "$HOME\tools\StealthHumanizer" run cli -- providers
```

The repo update script applies `patches/stealthhumanizer-cpa.patch` to the local clone. That patch adds `cpa-gpt-55` (`cx/gpt-5.5`) and `cpa-gemini-35-flash` (`ag/gemini-3.5-flash-low`) providers and auto-loads CLIProxyAPI config from local OpenCode config without committing secrets.

Use the agent for clarity, style, grammar, readability, and diagnostic detector-style scoring. Do not use it to hide AI authorship, bypass institutional detectors, or remove required provenance/citations.

## GSD Orchestrator

This setup includes a unified `gsd` agent that ports GSD (Get Shit Done) orchestration into OpenCode without installing the full 86+ slash-command pack.

Use it for end-to-end feature work, e.g.:

```text
Use the gsd agent in auto mode to plan, implement, verify, and prepare this feature for PR.
```

Supported GSD-style controls:

| Control | Values | Purpose |
| --- | --- | --- |
| Mode | `interactive`, `auto`, `yolo` | Controls autonomy and checkpoint behavior. |
| Granularity | `standard`, `detailed`, `minimal` | Controls plan/delegation detail. |
| Model profile | `balanced`, `performance`, `efficient`, `max` | Routing hint for subagent model selection and delegation depth. |

The agent is a meta-orchestrator: it applies GSD methodology and delegates to existing OpenCode agents (`plan`, `build`, `review`, `explore`, `scout`, `socraticode-explorer`, `stealthhumanizer`) instead of duplicating the full GSD command tree.

### Subagent Model Selection (Quota Protection)

Both the `gsd` and `openspec-engineer` agents default all subagents to `9router/ag/gemini-3-flash-agent`:

- In `interactive` mode, the agent asks which model to use **once** at session start.
- In `auto`/`yolo` mode, it uses `9router/ag/gemini-3-flash-agent` without asking.
- The main session model is only used for the lead orchestrator's own reasoning.

The `compaction` agent also uses `9router/ag/gemini-3-flash-agent` to avoid burning expensive quota during context compaction.

### 9Router provider

This repo includes two sanitized OpenAI-compatible provider templates: legacy `cliproxyapi` and new `9router`. Live config must use real endpoints/keys locally; repo config uses `__SET_IN_LOCAL_ENV_OR_CONFIG__` placeholders.

When refreshing provider models, query the live endpoint first and copy exact IDs from `data[].id`:

```powershell
$env:NINEROUTER_BASE_URL = "https://your-proxy.example.com/v1"
$env:NINEROUTER_API_KEY = "__SET_IN_LOCAL_ENV_OR_CONFIG__"
curl.exe -s -H "Authorization: Bearer $env:NINEROUTER_API_KEY" "$env:NINEROUTER_BASE_URL/models"
```

Current AG defaults from `/v1/models`:

- Default: `9router/ag/gemini-3-flash-agent`
- Budget: `9router/ag/gemini-3.5-flash-low`
- Higher-quality option: `9router/ag/claude-sonnet-4-6`

## Update Tools

Run the update script to fetch the latest versions of GSD, OpenSpec, SocratiCode, StealthHumanizer, and sync updated assets into this repo:

```powershell
# Dry run first
powershell -ExecutionPolicy Bypass -File scripts/update-tools.ps1 -DryRun

# Apply updates
powershell -ExecutionPolicy Bypass -File scripts/update-tools.ps1
```

The script:
1. Checks current vs. latest versions of all npm tools.
2. Re-runs the GSD installer (`npx get-shit-done-cc@latest --opencode --global --non-interactive`) to adopt latest commands/agents/workflows.
3. Syncs live `.opencode/` assets back into this repo (respecting sync-manifest rules).
4. Sanitizes `opencode.json` → `opencode.example.json` (redacts secrets).
5. Runs `validate.ps1` to ensure no secrets leaked.

Flags: `-SkipNpm`, `-SkipSync`, `-SkipValidation` for partial runs.

For LLM agents performing updates, see [`docs/LLM-UPDATE-INSTRUCTIONS.md`](docs/LLM-UPDATE-INSTRUCTIONS.md) for the full step-by-step flow including safety rules, secret handling, and custom agent preservation.
