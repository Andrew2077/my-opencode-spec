# Security Policy

This is a private repo, but it must not contain secrets.

## Never commit

- API keys, provider tokens, OAuth tokens, passwords.
- `.env` files.
- Raw `.opencode/opencode.json` if it contains real keys or machine-local paths.
- Runtime databases such as `memory.db*` or session DBs.
- `node_modules/` or generated dependency folders.
- Backup/temp/log files that may contain copied secrets.

## Allowed

- `.env.example` with placeholder values only.
- `.opencode/opencode.example.json` with keys redacted as `__SET_IN_LOCAL_ENV_OR_CONFIG__`.
- Provider base URLs redacted to placeholders such as `https://your-proxy.example.com/v1`.
- Source files for agents, skills, tools, plugins, docs, and scripts.

## Pre-commit checklist

```powershell
powershell -ExecutionPolicy Bypass -File scripts/validate.ps1
git status --short
git diff --cached
```

Review every file in the staged diff. If a secret appears, remove it from Git history before pushing and rotate the secret.

Also reject private provider endpoints in tracked files, including Tailscale/CGNAT `100.64.0.0/10`, RFC1918, and localhost URLs.

## GitHub visibility

Create the GitHub repo with `--private`:

```bash
gh repo create OWNER/my-opencode-spec --private --source . --remote origin
```

Do not push until private visibility and staged files are verified.

## If a secret is committed

1. Treat it as compromised.
2. Rotate/revoke it immediately.
3. Remove it from the repo and history before pushing.
4. Re-run validation.
