# Muzzle: Workflow Authoring Guide

## Overview

Muzzle workflows are scripts in any supported language. Kujo (`.kujo`) is the default runner.

## Quick Workflow (Kujo — default)

Create `.muzzle/workflows/my-workflow.kujo`:

```kujo
// My Workflow — a brief description
print("Starting my workflow...")
// ... your Kujo logic here ...
print("Done.")
```

Run it:

```bash
muzzle run my-workflow
```

## Quick Workflow (Bash)

Create `.muzzle/workflows/my-workflow.sh`:

```bash
#!/usr/bin/env bash
# My Workflow — a brief description
set -euo pipefail

echo "Starting my workflow..."
# ... your commands here ...
echo "Done."
exit 0
```

Make it executable:

```bash
chmod +x .muzzle/workflows/my-workflow.sh
```

Run it:

```bash
muzzle run my-workflow
```

## Manifest File (Optional)

Create `.muzzle/manifests/my-workflow.json` for rich metadata:

```json
{
  "name": "my-workflow",
  "summary": "Brief one-line description of what this workflow does.",
  "runner": "bash",
  "script": "workflows/my-workflow.sh",
  "args": [
    {
      "name": "target",
      "required": true,
      "description": "The deployment target."
    },
    {
      "name": "branch",
      "required": false,
      "description": "Git branch to deploy from (default: main)."
    }
  ],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": false,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
```

### Manifest Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Workflow name (must match filename without extension) |
| `summary` | No | One-line description shown in `muzzle list` |
| `runner` | No | Override runner: `kujo`, `bash`, `python`, or `node` |
| `script` | Yes | Path relative to `.muzzle/` directory |
| `args` | No | Array of argument definitions |
| `args[].name` | Yes | Argument name |
| `args[].required` | No | Whether the argument is required (default: false) |
| `args[].description` | No | Human-readable description |
| `quiet_by_default` | No | Hint that this workflow should be quiet (default: true) |
| `safety` | No | Safety metadata object |
| `safety.require_git_repo` | No | Whether workflow needs a git repo (informational) |
| `safety.allow_dirty_tree` | No | Whether uncommitted changes are OK (informational) |
| `safety.requires_network` | No | Whether workflow needs network access (informational) |
| `safety.human_approval_recommended` | No | Whether a human should approve before running |

The `script` value can name a shared implementation, such as `workflows/shared-verify.sh`, even when the manifest is named `project-verify.json`. Muzzle resolves the path under `.muzzle/workflows/` and rejects traversal or symlink escapes before execution.

## Argument Handling

Workflow arguments are passed positionally:

```bash
# In your workflow script:
TARGET="${1:-}"
BRANCH="${2:-main}"

echo "Deploying to ${TARGET} from ${BRANCH}"
```

Usage:

```bash
muzzle run deploy production
muzzle run deploy staging develop
muzzle run lint -- --fix
```

Use `--` before workflow arguments that begin with `-`; otherwise known Muzzle run flags such as `--json`, `--timeout`, and `--runner` are interpreted by Muzzle.

## Output Conventions

### Standard Output
- Muzzle captures all stdout/stderr to `.muzzle/logs/<name>-<timestamp>.log`
- The compact summary only shows status, exit code, duration, and file paths
- Use `--verbose` to stream output to terminal during execution

### Exit Codes
- Exit 0 for success
- Exit non-zero for failure (propagated by Muzzle)
- Muzzle exits 1 if the workflow script is not found

### Secrets
- Never `echo` tokens, keys, or credentials
- If you must, know that Muzzle attempts to redact common patterns from summaries
- Full logs preserve all output — keep `.muzzle/logs/` out of version control

## Best Practices

1. **Use `set -euo pipefail`** at the top of workflow scripts
2. **Validate inputs** — check required arguments exist before using them
3. **Exit clearly** — use explicit `exit 0` or `exit 1`
4. **Keep it simple** — one workflow, one responsibility
5. **Document in the manifest** — a good summary helps agents and humans
6. **Mark safety flags honestly** — `human_approval_recommended: true` for dangerous workflows
7. **Add `.muzzle/logs/` and `.muzzle/reports/` to `.gitignore`**
8. **Keep scripts under `.muzzle/workflows/`** — manifest aliases are supported, but symlinks or paths that resolve outside the workflow directory are rejected

## Examples

### build-check

```bash
#!/usr/bin/env bash
# Check if the project builds successfully
set -euo pipefail

if [[ -f "package.json" ]]; then
    echo "Found package.json — running npm build check..."
    npm run build --if-present 2>&1 || {
        echo "Build check failed"
        exit 1
    }
elif [[ -f "Makefile" ]]; then
    echo "Found Makefile — running make..."
    make 2>&1 || {
        echo "Make failed"
        exit 1
    }
else
    echo "No build system detected. Nothing to check."
fi

echo "Build check complete."
```

### repo-status

```bash
#!/usr/bin/env bash
# Show current repository status (read-only)
set -euo pipefail

if ! git rev-parse --git-dir &>/dev/null; then
    echo "Not a git repository."
    exit 1
fi

section_seen=0
section() {
    if [[ "$section_seen" -eq 1 ]]; then
        echo ""
    fi
    section_seen=1
    echo "=== $1 ==="
}

section "Git Status"
git status --short

section "Current Branch"
git branch --show-current

section "Remotes"
git remote -v

section "Last 3 Commits"
git log --oneline -3
```
