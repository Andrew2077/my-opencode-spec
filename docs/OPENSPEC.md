# OpenSpec with this OpenCode setup

## Install OpenSpec CLI

Official package:

```bash
npm install -g @fission-ai/openspec@latest
openspec --version
```

OpenSpec requires Node.js `20.19.0` or newer.

Avoid the stale unscoped `openspec` npm package and the nonexistent `@openspec/cli` package.

## Initialize OpenSpec in a project

For OpenCode integration:

```bash
openspec init --tools opencode
```

Common generated structure:

```text
openspec/
├── specs/
├── changes/
└── config.yaml
```

OpenSpec may also generate OpenCode-facing skills and commands under `.opencode/` with names like `openspec-*` and `opsx-*`. Keep those generated assets separate from your custom skills and commands.

## Daily workflow

Core flow:

```text
/opsx:propose → /opsx:apply → /opsx:sync → /opsx:archive
```

Useful CLI checks:

```bash
openspec list
openspec validate --all --json
openspec status --change <change-id> --json
```

## Updating OpenSpec-generated assets

After upgrading OpenSpec or changing workflow profile:

```bash
npm install -g @fission-ai/openspec@latest
openspec update
```

To change profile/workflow selection:

```bash
openspec config profile
openspec update
```

## Using OpenSpec with your skills

- Use OpenSpec for spec/change workflow and artifact generation.
- Use your `.opencode/skill/` library for execution discipline, verification, UI, security, research, and OpenCode-specific workflows.
- Do not hand-edit generated OpenSpec assets unless necessary; prefer `openspec update`.
- If generated OpenSpec paths differ by version, keep the generated namespaced files and re-run this repo's fetch script to sync them.

## Recommended combined workflow

1. Install this OpenCode setup on the machine.
2. In each project, run `openspec init --tools opencode`.
3. Use `/opsx:propose` for behavior-level changes.
4. Use custom skills for implementation quality gates, e.g. `test-driven-development`, `verification-before-completion`, `security-and-hardening`, and `requesting-code-review`.
5. Run `openspec validate --all --json` before archiving changes.
