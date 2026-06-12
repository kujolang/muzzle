# Muzzle: How-To Guide

Step-by-step instructions to install, configure, and use Muzzle — from zero to running workflows in under 5 minutes.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Install the Kujo Language Runtime](#step-1-install-the-kujo-language-runtime)
- [Step 2: Install Muzzle](#step-2-install-muzzle)
- [Step 3: Verify the Installation](#step-3-verify-the-installation)
- [Step 4: Initialize a Project](#step-4-initialize-a-project)
- [Step 5: Create Your First Workflow](#step-5-create-your-first-workflow)
- [Step 6: Run a Workflow](#step-6-run-a-workflow)
- [Command Reference](#command-reference)
- [Output Modes](#output-modes)
- [Working with Runners](#working-with-runners)
- [Loop Mode for Multi-Step Tasks](#loop-mode-for-multi-step-tasks)
- [Workflow Manifests (Optional Metadata)](#workflow-manifests-optional-metadata)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

---

## Prerequisites

Before installing Muzzle, you need:

| Requirement | Version | Check Command |
|---|---|---|
| **Kujo language runtime** | 0.1.0+ | `$KUJO_BIN --version` |
| **Bash** | 3.2+ | `bash --version` |
| **Git** (optional) | any | `git --version` |

> **Important**: The Kujo **language** runtime is NOT the Python linter named `kujo` on PyPI. It is a separate language with its own binary. You must build it from source or have the binary available.

---

## Step 1: Install the Kujo Language Runtime

Muzzle is written in the Kujo language and requires the Kujo runtime to execute.

### Option A: Build from source (recommended)

```bash
# Clone the Kujo language repository
git clone https://github.com/kujolang/kujo.git
cd kujo

# Build the runtime (requires Rust toolchain)
cargo build

# The binary is at target/debug/kujo (or target/release/kujo for --release)
```

### Option B: Use an existing Kujo binary

If you already have the Kujo runtime built elsewhere, note the path to the binary.

### Set the KUJO_BIN environment variable

Add this to your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.bash_profile`):

```bash
export KUJO_BIN=/path/to/kujo/target/debug/kujo
```

Verify it works:

```bash
$KUJO_BIN --version
# Expected output: kujo x.y.z (or similar version info)
```

---

## Step 2: Install Muzzle

### Clone the repository

```bash
git clone https://github.com/kujolang/muzzle.git
cd muzzle
```

### Add Muzzle to your PATH

Add this to your shell profile:

```bash
export PATH="/path/to/muzzle:$PATH"
```

Then reload your shell:

```bash
source ~/.zshrc   # or ~/.bashrc
```

Alternatively, run Muzzle directly with its full path:

```bash
/path/to/muzzle/muzzle <command>
```

### How the wrapper works

The `muzzle` script is a thin Bash wrapper. It:

1. Locates the Kujo runtime via `$KUJO_BIN` or common paths
2. Invokes `muzzle.kujo` in interpreter mode for cross-module support
3. Passes all arguments through to the Kujo program

You usually invoke the wrapper directly; it handles the runtime handoff for you.

---

## Step 3: Verify the Installation

Run the help command to confirm everything works:

```bash
muzzle --help
```

Expected output:

```
Muzzle v0.2.0 — Quiet Workflow Runner for AI-Assisted Development

Usage:
  kujo run muzzle.kujo -- <command> [options]
  muzzle <command> [options]

Commands:
  init                          Initialize .muzzle/ in current directory
  list                          List available workflows
  info <workflow>               Show workflow details
  run <workflow> [args...]      Run a workflow quietly
  ...
```

If you see parse errors or "Undefined function" warnings, see [Troubleshooting](#troubleshooting).

Both `muzzle help` and `muzzle --help` work, and the same is true for `muzzle version` / `muzzle --version`.

---

## Step 4: Initialize a Project

Navigate to any project directory and run:

```bash
cd /path/to/your/project
muzzle init
```

This creates the `.muzzle/` directory with the following structure:

```
.muzzle/
├── workflows/
│   ├── hello.kujo          # Example Kujo workflow
│   └── hello-bash.sh       # Example Bash workflow
├── manifests/
│   ├── hello.json          # Metadata for hello.kujo
│   └── hello-bash.json     # Metadata for hello-bash.sh
├── logs/                   # Full output capture (.log files)
├── reports/                # Markdown + JSON reports
├── state/
│   ├── session.json        # Session tracking
│   └── loops/              # Loop state files
└── .gitignore              # Ignores logs, reports, and state
```

Verify the initialization worked:

```bash
muzzle list
```

Expected output:

```
WORKFLOW             RUNNER   SUMMARY
--------             ------   -------
hello                kujo     Simple hello-world workflow (Kujo runner). Safe and read-only.
hello-bash           bash     Simple hello-world workflow (Bash runner). Safe and read-only.
```

---

## Step 5: Create Your First Workflow

### A Kujo workflow (default runner)

Create `.muzzle/workflows/build.kujo`:

```bash
cat > .muzzle/workflows/build.kujo << 'EOF'
// Build Workflow — compiles the project and runs checks.
func print_lines(items) {
	mut idx := 0
	while idx < len(items) {
		print(items[idx])
		idx = idx + 1
	}
}

print_lines(array(
	"Step 1: Cleaning build artifacts...",
	"Step 2: Compiling source files...",
	"Step 3: Running static analysis...",
	"",
	"Build complete. All checks passed.",
	"Output: dist/myproject.tar.gz"
))
EOF
```

Run it:

```bash
muzzle run build
```

### A Bash workflow

Create `.muzzle/workflows/deploy.sh`:

```bash
cat > .muzzle/workflows/deploy.sh << 'EOF'
#!/usr/bin/env bash
# Deploy Workflow — pushes the project to a target environment.
set -euo pipefail

TARGET="${1:-staging}"
BRANCH="${2:-main}"

echo "Deploying to: ${TARGET}"
echo "Branch:        ${BRANCH}"
echo "Timestamp:     $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

for step in "Building..." "Testing..." "Pushing..."; do
  echo "$step"
  sleep 0.5
done
echo ""

echo "Deploy complete. ${TARGET} is live."
exit 0
EOF

chmod +x .muzzle/workflows/deploy.sh
```

Run it with arguments:

```bash
muzzle run deploy production main
```

### A Python workflow

Create `.muzzle/workflows/analyze.py`:

```bash
cat > .muzzle/workflows/analyze.py << 'EOF'
#!/usr/bin/env python3
"""Analyze Workflow — runs code quality checks."""
import sys
import time

target = sys.argv[1] if len(sys.argv) > 1 else "."
print(f"Analyzing: {target}")
print(f"Timestamp: {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}")
print()

for line in ["Running linter...", "Checking formatting...", "Counting lines of code..."]:
    print(line)
print()

print("Analysis complete. No issues found.")
EOF

chmod +x .muzzle/workflows/analyze.py
```

Run it:

```bash
muzzle run analyze src/
```

---

## Step 6: Run a Workflow

### Default (quiet) mode

```bash
muzzle run hello
```

Output:

```
Muzzle: hello

Status:     success
Exit code:  0
Duration:   245ms

Report:     .muzzle/reports/hello-1717000000.md
Log:        .muzzle/logs/hello-1717000000.log
```

The full output is captured in `.muzzle/logs/`. Only the summary is printed in the reviewed paths.

### Verbose mode — see everything

```bash
muzzle run hello --verbose
```

Streams all output to your terminal AND saves it to the log file.

### JSON mode — for scripts and agents

```bash
muzzle run hello --json
```

Returns a single JSON object that can be piped to `jq` or parsed programmatically:

```json
{
  "workflow": "hello",
  "status": "success",
  "exit_code": 0,
  "duration_ms": 245,
  "log_path": ".muzzle/logs/hello-1717000000.log",
  "report_path": ".muzzle/reports/hello-1717000000.md",
  "summary": "Hello from Muzzle!\nRunner: Kujo (default)\nThis is a sample workflow. Replace with your own.",
  "error_excerpt": null
}
```

### Dry run — preview without executing

```bash
muzzle run deploy production --dry-run
```

Prints the resolved runner, script path, and arguments without running anything.

### Setting a custom timeout

```bash
muzzle run long-task --timeout 600000   # 10 minutes (600,000 ms)
```

---

## Command Reference

| Command | Description |
|---|---|
| `muzzle help` / `muzzle --help` | Show usage information |
| `muzzle version` / `muzzle --version` | Print version number |
| `muzzle init` | Create `.muzzle/` directory structure in current directory |
| `muzzle list` | List all available workflows |
| `muzzle info <name>` | Show workflow details (runner, script, args, safety metadata) |
| `muzzle run <name> [args...]` | Execute a workflow quietly |
| `muzzle logs [name]` | Show log file paths for a workflow |
| `muzzle report [name]` | Show report file paths for a workflow |
| `muzzle loop start <wf> --limit <n>` | Start a stateful agent loop |
| `muzzle loop next` | Advance to next loop iteration |
| `muzzle loop done --note "..."` | Record completed iteration with a note |
| `muzzle loop status` | Show current loop progress |
| `muzzle loop summary` | Show all loop entries in a table |
| `muzzle clean` | Remove all logs and reports |

### Run flags

| Flag | Short | Description |
|---|---|---|
| `--verbose` | `-v` | Stream full output to terminal |
| `--dry-run` | `-n` | Preview execution without running |
| `--json` | | Output machine-readable JSON summary |
| `--runner <name>` | | Force runner: `kujo`, `bash`, `python`, or `node` |
| `--timeout <ms>` | | Max execution time in milliseconds (default: 300000, min: 1000, max: 3600000) |

---

## Output Modes

### Default (quiet)

- Prints a compact 5–6 line summary on success, up to 12 lines on failure
- Full stdout and stderr written to `.muzzle/logs/<name>-<timestamp>.log`
- Markdown and JSON reports written to `.muzzle/reports/`
- Secrets are redacted from the summary (full logs preserve all output)

### Verbose (`--verbose`)

- All output streams to the terminal in real time
- Simultaneously captured to the log file
- Secret redaction is **not** applied to terminal output (you chose to see everything)

### JSON (`--json`)

- Single JSON object printed to stdout
- All other messages go to stderr
- Ideal for piping to `jq`, shell scripts, or AI agent consumption

### Dry Run (`--dry-run`)

- Prints the resolved runner type, workflow script path, and arguments
- Does not execute anything
- Useful for verifying workflow discovery before running

---

## Working with Runners

Muzzle supports four runners. Kujo is the default.

| Runner | File Extension | Execution |
|---|---|---|
| **kujo** (default) | `.kujo` | `$KUJO_BIN run script.kujo` |
| **bash** | `.sh` | `bash script.sh` |
| **python** | `.py` | `python3 script.py` |
| **node** | `.js` | `node script.js` |

### How the runner is determined

1. **`--runner` flag** — explicit override (highest priority)
2. **Manifest `runner` field** — if a manifest exists for the workflow
3. **File extension** — `.kujo` → kujo, `.sh` → bash, `.py` → python, `.js` → node
4. **Default** — kujo

### Force a specific runner

```bash
# Run a .py script even if it would default to python
muzzle run analyze --runner python

# Force a .sh script to be treated as a bash runner
muzzle run deploy --runner bash
```

---

## Loop Mode for Multi-Step Tasks

Loop mode is designed for AI agents performing iterative work (fix-test cycles, release hardening, batch operations). It tracks state persistently.

### Start a loop

```bash
muzzle loop start release-hardening --limit 10
```

Output:

```
Muzzle Loop: release-hardening
Limit: 10 iterations
State:  .muzzle/state/loops/release-hardening.json

Next:  muzzle loop next
```

### Work through iterations

```bash
# Begin iteration 1
muzzle loop next
# Output: Loop 1/10: release-hardening

# ... do your work ...

# Mark iteration 1 complete
muzzle loop done --note "Fixed README commands against CLI help"
# Output: Iteration 1/10 done: Fixed README commands against CLI help

# Begin iteration 2
muzzle loop next
# Output: Loop 2/10: release-hardening

# ... do your work ...

muzzle loop done --note "Updated all doc examples to match CLI output"
```

### Check progress

```bash
muzzle loop status
```

### View all iterations

```bash
muzzle loop summary
```

Shows a table with iteration numbers, statuses, notes, and timestamps.

### Important notes

- Only one loop can be active at a time per project
- Loop state persists across shell sessions in `.muzzle/state/loops/`
- All `loop` commands must be run from the same project directory

---

## Workflow Manifests (Optional Metadata)

Manifests are JSON files in `.muzzle/manifests/` that provide rich metadata about a workflow. They are optional — Muzzle auto-discovers scripts by extension.

### Create a manifest

`.muzzle/manifests/deploy.json`:

```json
{
  "name": "deploy",
  "summary": "Build and deploy the static site to a target environment.",
  "runner": "bash",
  "script": "workflows/deploy.sh",
  "args": [
    {
      "name": "target",
      "required": true,
      "description": "Deployment target: staging or production."
    },
    {
      "name": "branch",
      "required": false,
      "description": "Git branch to deploy from (default: main)."
    }
  ],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": true,
    "allow_dirty_tree": false,
    "requires_network": true,
    "human_approval_recommended": true
  }
}
```

### Manifest fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Workflow name (must match filename without extension) |
| `summary` | No | One-line description shown in `muzzle list` |
| `runner` | No | Override runner: `kujo`, `bash`, `python`, or `node` |
| `script` | Yes | Path to script relative to `.muzzle/` directory |
| `args` | No | Array of argument definitions for documentation |
| `args[].name` | Yes | Argument name |
| `args[].required` | No | Whether the argument is required (default: false) |
| `args[].description` | No | Human-readable description of the argument |
| `quiet_by_default` | No | Hint for agent consumption (default: true) |
| `safety` | No | Safety metadata for future Leash integration |
| `safety.require_git_repo` | No | Whether workflow needs a git repository |
| `safety.allow_dirty_tree` | No | Whether uncommitted changes are OK |
| `safety.requires_network` | No | Whether workflow needs network access |
| `safety.human_approval_recommended` | No | Whether a human should approve before running |

### View workflow details

```bash
muzzle info deploy
```

Displays the runner, script path, argument list, and safety metadata from the manifest.

---

## Troubleshooting

### "Error: Kujo language runtime not found"

Muzzle cannot locate the Kujo binary.

1. Verify `$KUJO_BIN` is set:
   ```bash
   echo $KUJO_BIN
   ```
2. If empty, set it:
   ```bash
   export KUJO_BIN=/path/to/kujo/target/debug/kujo
   ```
3. Verify the binary works:
   ```bash
   $KUJO_BIN --version
   ```

### Parse errors or "Undefined Function" warnings

If you see diagnostic noise before the Muzzle output, your Kujo runtime may have a cross-module import resolution issue with the type checker. This is a known Kujo core limitation and does not affect functionality. The workflows still execute correctly. See `.dogfood/muzzle/kujo-core-fixes-handoff.md` for technical details.

**Workaround**: Redirect stderr to hide the diagnostics:

```bash
muzzle run hello 2>/dev/null
```

Or pipe through grep to filter:

```bash
muzzle run hello 2>&1 | grep -v "^\[RUF"
```

### "No .muzzle/ directory found"

Run `muzzle init` first in the project directory.

### Workflow name contains slashes or ".."

Muzzle rejects workflow names with `/`, `\`, or `..` for security. Use a simple alphanumeric name with hyphens.

### Script not found

Muzzle only looks inside `.muzzle/workflows/`. Verify your script is there:

```bash
ls -la .muzzle/workflows/
```

### Workflow times out

The default timeout is 5 minutes (300,000 ms). Increase it for long-running tasks:

```bash
muzzle run long-build --timeout 1800000   # 30 minutes
```

### "Permission denied" on a Bash script

Make sure the script is executable:

```bash
chmod +x .muzzle/workflows/my-workflow.sh
```

---

## Next Steps

- Read the [Workflow Authoring Guide](workflows.md) for detailed workflow creation tips
- Read the [Agent Usage Guide](agent-usage.md) if you're using Muzzle with AI coding assistants
- Read the [Security Model](security.md) to understand the guardrails and remaining limitations
- Explore the [Kujo language](https://github.com/kujolang/kujo) to write Kujo-native workflows
- Check the [issue tracker](https://github.com/kujolang/muzzle/issues) for known issues and planned enhancements

---

*Muzzle v0.2.0 — Part of the [Kujo/Kujo](https://github.com/kujolang/kujo) ecosystem.*
