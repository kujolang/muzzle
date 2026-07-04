# Muzzle

[![Version](https://img.shields.io/badge/version-1.0.0-black)](https://github.com/kujolang/muzzle)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![built with Kujo](https://img.shields.io/badge/built%20with-Kujo-white.svg)](https://github.com/kujolang/kujo)

**Quiet workflow runner for AI-assisted development - built in Kujo.**

Muzzle is a **workflow compression layer** that keeps noisy, repeated command output out of AI agent context. It runs known local workflows with quieter terminal output, captures full logs to disk, and returns compact, agent-friendly summaries.

```
$ muzzle run deploy website-name

Muzzle: deploy website-name

Status:     success
Exit code:  0
Duration:   18420ms

Report:     .muzzle/reports/deploy-1780000000.md
Log:        .muzzle/logs/deploy-1780000000.log

Use --verbose for full output or --json for machine-readable format.
```

The full build log, deploy JSON, and terminal output stay on disk. In the reviewed flows, your agent often sees just a short summary instead of hundreds of lines.

## Why Muzzle Exists

AI-assisted development wastes expensive model context on predictable operational noise:

| Waste Source | Without Muzzle | With Muzzle |
|---|---|---|
| Build output (200 lines) | ~200 lines in context | 6-line summary |
| Deploy JSON response | ~50 lines | 6-line summary |
| Test suite (500 lines) | ~500 lines | 6–12 lines |
| 10-iteration loop instructions | Repeated prompts | Loop state tracking |

Muzzle is designed to keep the signal in context and leave the full run on disk for later review. Every command returns deterministic exit codes, machine-readable JSON, and structured reports that downstream tools can consume.

## Readiness

Muzzle is ready for trusted local workflow compression in real projects: it initializes predictable workflow folders, runs Kujo/Bash/Python/Node scripts, preserves full logs, emits compact summaries, and keeps machine-readable reports stable enough for agents and shell automation.

It is not a sandbox for untrusted code and it is not yet a frozen enterprise platform API. Treat workflow scripts like any other local automation: review them, document risk in manifests, use `--dry-run` for sensitive flows, and keep logs/reports out of version control. The current goal is a polished, production-useful Kujo showcase with a deliberately stabilizing CLI and manifest surface.

## Architecture

```
muzzle (Bash wrapper)
  └─ $KUJO_BIN run muzzle.kujo --interpreter -- <command>
       ├─ src/common.kujo      CLI parsing, timestamps, helpers
       ├─ src/runner.kujo      Modular dispatch (kujo/bash/python/node)
       ├─ src/workflow.kujo    Discovery, manifest loading, validation
       ├─ src/report.kujo      Markdown + JSON report generation
       ├─ src/redact.kujo      Multi-line secret redaction
       └─ src/loops.kujo       Stateful agent loop management
```

Muzzle is a **Kujo-native** CLI with a thin Bash wrapper for PATH convenience. The wrapper auto-discovers the Kujo runtime via `KUJO_BIN` or common paths and filters known debug-only Kujo optimizer stats so Muzzle's own output stays quiet. The root-level `muzzle` wrapper and `muzzle.kujo` entrypoint are both intentional: the rest of the implementation lives in `src/`.

## Quick Start

```bash
git clone https://github.com/kujolang/muzzle.git
cd muzzle
export PATH="$PWD:$PATH"

cd /path/to/your/project
muzzle init
muzzle list
muzzle run hello
muzzle run hello --json
```

Useful follow-ups:

```bash
muzzle info hello                     # show workflow details
muzzle run hello-bash                 # use the Bash runner example
muzzle run deploy production --dry-run
muzzle run build --verbose
muzzle run long-task --timeout 60000
muzzle run lint -- --fix              # pass a literal leading-dash arg to the workflow
```

Agents and contributors should also read [`AGENTS.md`](AGENTS.md) for canonical examples, search exclusions, and copyable example style.

## Commands

| Command | Description |
|---|---|
| `muzzle init` | Initialize `.muzzle/` in current directory |
| `muzzle list` | List available workflows |
| `muzzle info <name>` | Show workflow details (runner, script, args, safety) |
| `muzzle run <name> [args...]` | Execute a workflow quietly |
| `muzzle logs [name]` | Show log file paths |
| `muzzle report [name]` | Show report file paths |
| `muzzle loop start <wf> --limit <n>` | Start a stateful agent loop |
| `muzzle loop next` | Advance to next loop iteration |
| `muzzle loop done --note "..."` | Record completed iteration |
| `muzzle loop status` | Show loop progress |
| `muzzle loop summary` | Show all loop entries in table |
| `muzzle clean` | Remove all logs and reports |
| `muzzle help` / `muzzle --help` | Show usage information |
| `muzzle version` / `muzzle --version` | Print version |

## Run Options

| Flag | Description |
|---|---|
| `--verbose`, `-v` | Stream full output to terminal |
| `--dry-run`, `-n` | Print what would execute without running |
| `--json` | Output machine-readable JSON summary |
| `--runner <name>` | Force runner: `kujo` (default), `bash`, `python`, `node` |
| `--timeout <ms>` | Max execution time in ms (default: 300000, min: 1000, max: 3600000) |
| `--` | End Muzzle option parsing; remaining values are passed as workflow args |

## Runners

Muzzle supports multiple workflow runners. Kujo is the default.

| Runner | Extension | Execution | Use Case |
|---|---|---|---|
| **kujo** | `.kujo` | `$KUJO_BIN run script.kujo` | Kujo-native workflows, ecosystem integration |
| **bash** | `.sh` | `bash script.sh` | Shell scripts, existing build/deploy tooling |
| **python** | `.py` | `python3 script.py` | Python automation scripts |
| **node** | `.js` | `node script.js` | Node.js build/tooling scripts |

The runner is determined by: CLI `--runner` flag → manifest `runner` field → file extension → default (kujo).

## Output Modes

### Default (quiet)
Compact summary. Full output written to `.muzzle/logs/`. Success output is ≤6 lines.

### Verbose (`--verbose`)
Full output streams to terminal AND is captured to log file.

### JSON (`--json`)
Single JSON object on stdout with status, exit code, duration, and file paths. Everything else on stderr.

### Dry Run (`--dry-run`)
Prints the resolved runner, script path, and arguments without executing.

## Project Structure

```
project/
  .muzzle/
    workflows/         # Your workflow scripts
      hello.kujo       # Kujo workflow (default runner)
      deploy.sh        # Bash workflow
      analyze.py       # Python workflow
    manifests/         # Optional metadata per workflow (.json)
      hello.json
      deploy.json
    logs/              # Full stdout/stderr capture (.log)
    reports/           # Markdown + JSON reports (.md, .json)
    state/             # Session and loop state
      session.json
      loops/
  .gitignore           # Ignores .muzzle/logs/, .muzzle/reports/, .kujo_cache/
```

## Defining Workflows

### Quick: Drop a script into `.muzzle/workflows/`

Muzzle auto-discovers scripts by extension. No manifest required.

```bash
# Kujo workflow (default runner)
cat > .muzzle/workflows/build.kujo << 'EOF'
print("Building project...")
// Your Kujo build logic here
print("Done.")
EOF

muzzle run build
```

```bash
# Bash workflow
cat > .muzzle/workflows/deploy.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "Deploying ${1:-production}..."
# Your deploy logic
echo "Done."
EOF
chmod +x .muzzle/workflows/deploy.sh

muzzle run deploy production
```

### Better: Add a manifest for metadata

Create `.muzzle/manifests/<name>.json`:

```json
{
  "name": "deploy",
  "summary": "Build and deploy a static site.",
  "runner": "bash",
  "script": "workflows/deploy.sh",
  "args": [
    {"name": "target", "required": true, "description": "Deployment target."}
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

Manifests power `muzzle info`, safety metadata, stable aliases, and future Leash approval integration. The `script` path is relative to `.muzzle/`, must resolve under `.muzzle/workflows/`, and may point to a differently named implementation script.

## Loop Mode

For multi-step agent workflows with progress tracking:

```bash
muzzle loop start release-hardening --limit 10
muzzle loop next          # "Loop 1/10: release-hardening"
# ... agent does the work ...
muzzle loop done --note "Fixed README commands against CLI help"
muzzle loop next          # "Loop 2/10: release-hardening"
muzzle loop status        # Shows progress and entries
muzzle loop summary       # Full table of all iterations
```

## Safety

- **Path confinement**: Scripts must reside under `.muzzle/workflows/`. Path traversal (`..`) and slashes in workflow names are rejected.
- **Canonical script checks**: Manifest script paths and symlinks are resolved before execution; scripts that escape `.muzzle/workflows/` are rejected.
- **Argument safety**: Workflow arguments are shell-quoted as literal strings before execution, so shell metacharacters stay literal.
- **Secret redaction**: Case-insensitive single-line patterns (tokens, keys, credentials) + 9 multi-line block patterns (PEM keys, certificates) are redacted from summaries.
- **Full logs preserved**: Redaction applies only to summaries. Complete output is always available in `.muzzle/logs/`.
- **Input validation**: Workflow names are validated for length (≤128 chars) and forbidden characters (`/`, `\`, `..`).
- **Timeout protection**: Configurable per-run timeout (default: 5 minutes, max: 1 hour).
- **Example workflows are safe**: The built-in `hello` and `hello-bash` workflows are read-only in the reviewed paths.
- Read [`docs/security.md`](docs/security.md) for the full security model.

## Requirements

- **Kujo language runtime** — available via `KUJO_BIN` env var or auto-discovered from common paths
- **Bash 3.2+** — for the launcher wrapper and Bash-runner workflows
- The built-in example workflows shown here require no external dependencies, API keys, or network access

## Ecosystem

Muzzle is part of the [Kujo](https://github.com/kujolang/kujo) ecosystem and a showcase for Kujo as a tool-building language:

| Tool | Role |
|---|---|
| [Kujo](https://github.com/kujolang/kujo) | Language runtime — Muzzle is built in Kujo |
| [Spec](https://github.com/kujolang/spec) | Task definition — `muzzle.spec.yml` |
| [Eval](https://github.com/kujolang/eval) | Validation framework — verifies Muzzle behavior |
| [Scout](https://github.com/kujolang/scout) | Codebase intelligence — discovers repo workflows |
| [Dispatch](https://github.com/kujolang/dispatch) | Workflow orchestration — composes Muzzle steps |
| [Kennel](https://github.com/kujolang/kennel) | Package manager — distributes Muzzle |
| [Leash](https://github.com/kujolang/leash) | Mobile approval — approves dangerous workflows |
| [MCP](https://github.com/kujolang/mcp) | Agent protocol — exposes Muzzle as MCP tools |

## Status

**Active development** — v0.2.0. The reviewed CLI surface is functional for trusted local workflow capture, report generation, manifest-backed aliases, loop tracking, and agent-facing summaries. The public API (CLI surface, JSON report schema, manifest format) is stabilizing but not yet frozen. See the [issue tracker](https://github.com/kujolang/muzzle/issues) for known issues and planned enhancements.

## License

MIT — see [LICENSE](LICENSE) file.
