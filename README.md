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

Muzzle is designed to keep the signal in context and leave the full run on disk for later review. Commands return deterministic exit codes, while `muzzle run --json` emits a machine-readable summary and every executed run writes structured reports for downstream tools.

## Readiness

Muzzle is production-ready for trusted local workflow compression in real projects: it spools complete logs with bounded in-process capture, terminates Unix process trees on timeout/cancellation, validates manifests strictly, supports opt-in execution policy, and emits versioned machine-readable results for automation.

It is not a sandbox for untrusted code or an enterprise isolation boundary. Treat workflow scripts like any other local automation: review them, document risk in manifests, use `--dry-run` for sensitive flows, and keep logs/reports out of version control. The 1.0 CLI, JSON summary, and manifest contracts are stable within that trusted-local scope.

## Architecture

```
muzzle (Bash wrapper)
  └─ kujo run muzzle.kujo --interpreter -- <command>
       ├─ src/common.kujo      CLI parsing, timestamps, helpers
       ├─ src/runner.kujo      Modular dispatch (kujo/bash/python/node)
       ├─ src/workflow.kujo    Discovery, manifest loading, validation
       ├─ src/policy.kujo      Safety, argument, and signed-bundle policy
       ├─ src/doctor.kujo      Runtime and project diagnostics
       ├─ src/retention.kujo   Bounded artifact cleanup
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
muzzle run long-task --timeout 60000 --cancel-file .cancel-muzzle
muzzle run deploy production --policy enforce --approve --validate-args
muzzle doctor --json
muzzle run lint -- --fix              # pass a literal leading-dash arg to the workflow
```

Agents and contributors should also read [`AGENTS.md`](AGENTS.md) for canonical examples, search exclusions, and copyable example style.

For a copyable manifest-backed Bash workflow, see [`examples/build-check/`](examples/build-check/). Contributors can run the complete local gate with `make quality`.

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
| `muzzle clean` | Remove recognized Muzzle logs and reports |
| `muzzle doctor [--json]` | Validate manifests, runners, boundaries, and writable state |
| `muzzle integrity <name> [--json]` | Verify an optional script SHA-256 pin |
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
| `--cancel-file <path>` | Cancel when a safe project-relative marker file appears |
| `--policy trusted\|enforce` | Preserve trusted-local behavior or enforce manifest safety metadata |
| `--approve` | Confirm network/approval-marked work in enforce mode |
| `--validate-args` | Enforce required arguments, allowlists, and arity |
| signed policy flags | Verify a detached OpenSSL signature and authorize the workflow |
| `--` | End Muzzle option parsing; remaining values are passed as workflow args |

## Runners

Muzzle supports multiple workflow runners. Kujo is the default.

| Runner | Extension | Execution | Use Case |
|---|---|---|---|
| **kujo** | `.kujo` | `kujo run script.kujo` | Kujo-native workflows, ecosystem integration |
| **bash** | `.sh` | `bash script.sh` | Shell scripts, existing build/deploy tooling |
| **python** | `.py` | `python3 script.py` | Python automation scripts |
| **node** | `.js` | `node script.js` | Node.js build/tooling scripts |

The runner is determined by: CLI `--runner` flag → manifest `runner` field → file extension → default (kujo).

## Output Modes

### Default (quiet)
Compact summary. Full output is written to `.muzzle/logs/`; the terminal shows status, timing, artifact paths, and one follow-up hint.

### Verbose (`--verbose`)
Bounded captured output is printed after execution and retained in full in the log file. If the terminal display limit is reached, Muzzle points to the complete log.

### JSON (`--json`)
Single versioned JSON object on stdout. Workflow results use `muzzle.run/v1`, inspection commands use `muzzle.command/v1`, and command failures use `muzzle.error/v1`. Workflow reports include timeout, cancellation, and display-truncation fields. Schemas live in [`schemas/`](schemas/).

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
  "schema_version": "muzzle.manifest/v1",
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

Manifests power `muzzle info`, strict argument validation, opt-in policy enforcement, stable aliases, and checksum verification. Unknown fields and invalid types are rejected. The `script` path is relative to `.muzzle/`, must resolve under `.muzzle/workflows/`, and may point to a differently named implementation script.

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
- **Argument safety**: Workflow and helper execution use structured argument arrays; shell metacharacters stay literal.
- **Secret redaction**: Case-insensitive single-line patterns (tokens, keys, credentials) + 9 multi-line block patterns (PEM keys, certificates) are redacted from summaries.
- **Full logs preserved privately**: Redaction applies only to summaries. Complete output is available in `.muzzle/logs/`; Muzzle-owned logs and reports use owner-only file permissions on supported Unix systems.
- **Input validation**: Workflow names are validated for length (≤128 chars) and forbidden characters (`/`, `\`, `..`).
- **Process lifecycle**: Timeout exits 124; cancellation or forwarded interruption exits 130 and terminates the Unix process group.
- **Policy and provenance**: Enforce mode, script checksums, and optional signed policy bundles fail closed without claiming sandbox isolation.
- **Example workflows are safe**: The built-in `hello` and `hello-bash` workflows are read-only in the reviewed paths.
- Read [`docs/security.md`](docs/security.md) for the full security model.

## Requirements

- **Kujo language runtime 1.0.0+** — available via `KUJO_BIN` env var or auto-discovered from common paths
- **Bash 3.2+** — for the launcher wrapper and Bash-runner workflows
- **Unix tools** — `tail`; optional `openssl` for signed policy bundles
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

**Stable 1.0** — The reviewed CLI surface is stable for trusted local workflow capture, report generation, manifest-backed aliases, loop tracking, and agent-facing summaries. Muzzle remains local automation rather than a security sandbox. See the [issue tracker](https://github.com/kujolang/muzzle/issues) for future enhancements.

Linux and macOS are supported and exercised in CI. Native Windows launch is not supported; use WSL. For a versioned installation, run `bash scripts/install.sh --prefix /absolute/prefix`; Bash and Zsh completions are in [`completions/`](completions/).

The completed hardening review is recorded in [`docs/next-session-hardening.md`](docs/next-session-hardening.md), performance methodology in [`docs/performance.md`](docs/performance.md), and the next bounded roadmap in [`docs/next-session-roadmap.md`](docs/next-session-roadmap.md).

## License

MIT — see [LICENSE](LICENSE) file.
