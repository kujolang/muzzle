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
  "schema_version": "muzzle.manifest/v1",
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
| `schema_version` | No | When present, must be `muzzle.manifest/v1` |
| `summary` | No | One-line description shown in `muzzle list` |
| `runner` | No | Override runner: `kujo`, `bash`, `python`, or `node` |
| `script` | Yes | Path relative to `.muzzle/` directory |
| `args` | No | Array of argument definitions |
| `args[].name` | Yes | Argument name |
| `args[].required` | No | Whether the argument is required (default: false) |
| `args[].description` | No | Human-readable description |
| `args[].allowed_values` | No | String allowlist enforced by `--validate-args` |
| `args[].sensitive` | No | Redact the value in dry-run output |
| `allow_extra_args` | No | Allow positional values beyond declared args (default: true) |
| `script_sha256` | No | Optional 64-character SHA-256 script integrity pin |
| `quiet_by_default` | No | Hint that this workflow should be quiet (default: true) |
| `safety` | No | Safety metadata object |
| `safety.require_git_repo` | No | Require a Git work tree in enforce mode |
| `safety.allow_dirty_tree` | No | Permit uncommitted changes in enforce mode |
| `safety.requires_network` | No | Require `--approve` in enforce mode |
| `safety.human_approval_recommended` | No | Require `--approve` in enforce mode |

The `script` value can name a shared implementation, such as `workflows/shared-verify.sh`, even when the manifest is named `project-verify.json`. Muzzle resolves the path under `.muzzle/workflows/` and rejects traversal or symlink escapes before execution.

Every run executes a private snapshot whose digest must match the script bytes Muzzle validated. `script_sha256` additionally binds those bytes to a manifest-reviewed value. The digest does not cover sibling helpers or other files loaded by the workflow.

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

Use `--` before workflow arguments that begin with `-`; otherwise known Muzzle run flags are interpreted by Muzzle. Use `--validate-args` to activate manifest checks; this remains opt-in for 1.0 compatibility.

## Output Conventions

### Readable Kujo output

Keep a tiny first workflow direct. Once static output becomes a menu, report,
or multi-step explanation, collect the lines locally so the workflow remains
easy to scan and copy:

```kujo
func print_lines(lines) {
	mut idx := 0
	while idx < len(lines) {
		print(lines[idx])
		idx = idx + 1
	}
}

print_lines(array(
	"=== Build Check ===",
	"",
	"1. Validate configuration",
	"2. Compile the project",
	"3. Run tests"
))
```

Use similarly small local helpers for repeated label/value or status lines, but
keep the workflow operation itself visible. Avoid generic rendering layers in
examples.

### Standard Output
- Muzzle captures all stdout/stderr to `.muzzle/logs/<name>-<timestamp>.log`
- The compact summary only shows status, exit code, duration, and file paths
- Use `--verbose` to print bounded captured output after execution; the complete output always remains in the log

### Exit Codes
- Exit 0 for success
- Exit non-zero for failure (propagated by Muzzle)
- Muzzle exits 1 if the workflow script is not found
- Muzzle exits 124 on timeout, 130 on cancellation/interruption, 2 on usage/schema errors, and 3 on policy/integrity denial

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
