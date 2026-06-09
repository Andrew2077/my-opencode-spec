# LLM Instructions: Fetch Upstream Updates & Sync

Use this document when an LLM or coding agent is asked to update this repo with the latest GSD, OpenSpec, SocratiCode, and StealthHumanizer changes.

## Prerequisites

- Node.js 20.19.0+ installed
- This repo cloned at `$REPO` (e.g. `~/Desktop/my-opencode-spec` or `$HOME\Desktop\my-opencode-spec`)
- Live OpenCode config at `$HOME/.opencode/`

## Step 1: Check current versions

```bash
npx get-shit-done-cc@latest --help 2>&1 | head -5
npx @fission-ai/openspec@latest --version
npm view socraticode version
npm view github:rudra496/StealthHumanizer version
```

Record old → new version changes.

## Step 2: Update npm packages

```bash
npm install -g @fission-ai/openspec@latest
```

GSD and SocratiCode are npx-invoked (no global install needed). StealthHumanizer is installed from its GitHub repo into `$HOME/tools/StealthHumanizer` because it is not published on npm.

```bash
mkdir -p "$HOME/tools"
if [ ! -d "$HOME/tools/StealthHumanizer/.git" ]; then
  git clone https://github.com/rudra496/StealthHumanizer "$HOME/tools/StealthHumanizer"
else
  git -C "$HOME/tools/StealthHumanizer" pull --ff-only
fi
npm --prefix "$HOME/tools/StealthHumanizer" ci
npm --prefix "$HOME/tools/StealthHumanizer" run cli:build
```

This setup applies `patches/stealthhumanizer-cpa.patch` after cloning/updating StealthHumanizer. The patch adds CPA providers `cpa-gpt-55` (`cx/gpt-5.5`) and `cpa-gemini-35-flash` (`ag/gemini-3.5-flash-low`) and lets the CLI read `provider.cliproxyapi.options` from `$HOME/.opencode/opencode.json` without duplicating secrets.

For OpenCode agent defaults, prefer AG models from the live `9router` `/v1/models` response. Never invent model IDs. Current default is `9router/ag/gemini-3-flash-agent`; budget fallback is `9router/ag/gemini-3.5-flash-low`. Preserve legacy `cliproxyapi` alongside `9router`; do not overwrite it.

## Step 3: Re-run GSD installer (fetches latest commands/agents/skills)

```bash
npx get-shit-done-cc@latest --opencode --global --non-interactive
```

This installs/updates GSD skills, commands, and agent files into `$HOME/.opencode/`.

**Important:** This may overwrite or add files in `$HOME/.opencode/command/` and `$HOME/.opencode/skill/`. It does NOT touch custom agents (`gsd.md`, `openspec-engineer.md`, `socraticode-explorer.md`, `stealthhumanizer.md`) or `opencode.json`.

## Step 4: Update OpenSpec generated assets

In any project with OpenSpec initialized:

```bash
openspec update
```

This re-generates OpenSpec instruction files, skills, and commands.

## Step 5: Sync live changes into this repo

### Option A: Use the update script (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/update-tools.ps1
```

This script:
1. Checks current vs latest versions
2. Re-runs GSD installer
3. Syncs live `.opencode/` assets back into repo (respecting `sync-manifest.json`)
4. Sanitizes `opencode.json` → `opencode.example.json` (redacts secrets)
5. Runs `validate.ps1`

### Option B: Manual sync (Linux/VPS or no PowerShell)

```bash
REPO="$HOME/my-opencode-spec"
SRC="$HOME/.opencode"
DST="$REPO/.opencode"

# Sync safe assets (skip secrets, databases, node_modules)
rsync -a \
  --exclude opencode.json \
  --exclude .env \
  --exclude 'memory.db*' \
  --exclude node_modules \
  --exclude '*.bak' \
  --exclude '*.backup' \
  --exclude '*.tmp' \
  --exclude '*.log' \
  "$SRC/" "$DST/"
```

Then manually create/update the sanitized config:

```bash
node <<'NODE'
const fs = require('fs');
const src = `${process.env.HOME}/.opencode/opencode.json`;
const dst = `${process.env.HOME}/my-opencode-spec/.opencode/opencode.example.json`;
if (!fs.existsSync(src)) { console.error('No live config found'); process.exit(1); }
const config = JSON.parse(fs.readFileSync(src, 'utf8'));

// Redact secrets
for (const [, provider] of Object.entries(config.provider || {})) {
  if (provider.options?.apiKey) provider.options.apiKey = '__SET_IN_LOCAL_ENV_OR_CONFIG__';
}

fs.writeFileSync(dst, JSON.stringify(config, null, 2) + '\n');
console.log('Sanitized config written to', dst);
NODE
```

When adding or refreshing `9router` models, query `/v1/models` with local-only credentials first and use exact `data[].id` values:

```bash
curl -s \
  -H "Authorization: Bearer $NINEROUTER_API_KEY" \
  "$NINEROUTER_BASE_URL/models"
```

Do not paste real endpoint URLs or keys into repo docs. Use placeholders such as `https://your-proxy.example.com/v1` and `__SET_IN_LOCAL_ENV_OR_CONFIG__`.

## Step 6: Preserve custom agents

**CRITICAL:** The GSD installer may create its own `gsd-*.md` agent files. Our custom agents (`gsd.md`, `openspec-engineer.md`, `socraticode-explorer.md`, `stealthhumanizer.md`) must NOT be overwritten.

After sync, verify these files are intact:
- `.opencode/agent/gsd.md` — our custom GSD orchestrator (not the upstream gsd-* agents)
- `.opencode/agent/openspec-engineer.md` — our custom OpenSpec agent
- `.opencode/agent/socraticode-explorer.md` — our SocratiCode agent
- `.opencode/agent/stealthhumanizer.md` — our StealthHumanizer writing-revision agent

If the GSD installer added `gsd-*` prefixed agent files, those are upstream GSD subagents. Keep them alongside our custom `gsd.md`.

## Step 7: Validate

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
git status --short --branch
git diff --check
```

```bash
# Linux
cd "$REPO"
# Check no secrets/private endpoints in tracked files.
# Use patterns for API key prefixes, bearer-token literals, and private endpoint fragments.
! grep -rn '<secret-patterns>' .opencode/ --include='*.json' --include='*.md' | grep -v example | grep -v '__SET_'
git status --short --branch
```

## Step 8: Review and commit

```bash
git diff --stat
git add .opencode/ scripts/ docs/ README.md
# Do NOT add: opencode.json, .env, memory.db*, node_modules/
git commit -m "chore: sync upstream GSD vX.Y.Z, OpenSpec vA.B.C, SocratiCode vD.E.F"
```

Only push after explicit user approval.

## Safety rules

1. **Never commit real secrets** — `opencode.json`, `.env` files stay untracked.
2. **Never overwrite custom agents** — `gsd.md`, `openspec-engineer.md`, `socraticode-explorer.md`, `stealthhumanizer.md` are hand-maintained.
3. **Always validate before commit** — run `validate.ps1` or equivalent.
4. **Preserve `sync-manifest.json` rules** — it defines what syncs and what doesn't.
5. **Report version changes** — state old → new version for each tool updated.
6. **Backup before overwrite** — if live config exists, backup with timestamp before any merge.

## Compaction agent model

The `compaction` agent must always use the current AG default. After any sync, verify this entry exists in `opencode.example.json`:

```json
"compaction": {
  "model": "9router/ag/gemini-3-flash-agent",
  "mode": "all"
}
```

If missing, add it. This ensures context compaction uses the AG default instead of the expensive main session model.
