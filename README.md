# Muzzle

[![Version](https://img.shields.io/badge/version-1.1.3-black)](https://github.com/kujolang/muzzle/releases/tag/v1.1.3)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)
[![built with Kujo](https://img.shields.io/badge/built%20with-Kujo-white.svg)](https://github.com/kujolang/kujo)

Run local workflows without filling your terminal or an AI agent's context with logs. Muzzle saves complete output to disk and returns the result, exit code, duration, and evidence paths.

Use it for builds, tests, checks, and other commands you run often. Inspect the full log when you need it. Use `--json` when another tool needs the result.

Muzzle runs trusted local code. It is not a sandbox. Review workflow scripts before running them, and keep logs, reports, and state out of version control.

## What's new in 1.1.3

This maintenance release updates the supported Node.js versions for runner tests and tooling.

### Included 1.1.2 improvements

This release includes the 1.1.1 hardening fixes and corrects Kennel's global command entrypoint. Upgrade global installations to 1.1.2.

- Safer initialization, cleanup, option parsing, and loop-state writes.
- Redacted failure excerpts that retain useful diagnostics without exposing distant secret blocks.
- Less repeated work in argument parsing, retention selection, and workflow snapshot preparation.
- Regression tests for failures, filesystem boundaries, and output contracts.

The CLI and versioned JSON contracts remain compatible. Existing projects should add `state/` to `.muzzle/.gitignore`; Muzzle preserves user-owned ignore files. Loop commands still require one writer per project. See the [changelog](CHANGELOG.md) and [audit reports](docs/audits/repository-hardening.md) for details and measurements.

## Quick Start

Install the [Kujo language runtime](https://docs.kujolang.ai/install/) first. Then use the released source:

```bash
git clone --branch v1.1.3 https://github.com/kujolang/muzzle.git
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

Read [`AGENTS.md`](AGENTS.md) before changing the repository. It lists the source reading order, examples, and search exclusions.

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
| `--verbose`, `-v` | Print bounded captured output after execution |
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

Kujo is the default runner. Use a manifest or `--runner` to choose another.

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
    .gitignore         # Ignores logs/, reports/, and state/
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

### Add a manifest

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

Manifests describe the workflow for `muzzle info` and support argument validation, policy enforcement, aliases, and checksum verification. Use `--validate-args` to enforce the argument contract. Unknown fields and invalid types are rejected. The `script` path is relative to `.muzzle/`, must resolve under `.muzzle/workflows/`, and may point to a differently named implementation script.

## Loop Mode

For multi-step agent workflows with progress tracking, use one loop writer per project. Serialize `start`, `next`, and `done`; concurrent loop writers are not currently coordinated.

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
- **Byte-bound execution**: Every run executes a private snapshot whose SHA-256 digest must match the bytes Muzzle validated, closing pathname replacement races for the workflow script.
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
- **Unix tools** — `awk`, `ln`, and `shasum` or `sha256sum`; optional `openssl` for signed policy bundles
- The built-in example workflows shown here require no external dependencies, API keys, or network access

## Ecosystem

Related Kujo tools:

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

**Stable v1.1.3.** The CLI, manifests, and versioned JSON contracts support trusted local workflows. The [issue tracker](https://github.com/kujolang/muzzle/issues) lists proposed changes.

The Bash launcher delegates to `muzzle.kujo`; implementation modules live in `src/`. Keep both root entrypoints when installing from source.

Linux and macOS are supported and exercised in CI. Native Windows launch is not supported; use WSL. For a versioned installation, run `bash scripts/install.sh --prefix /absolute/prefix`; Bash and Zsh completions are in [`completions/`](completions/).

The completed hardening review is recorded in [`docs/next-session-hardening.md`](docs/next-session-hardening.md), performance methodology in [`docs/performance.md`](docs/performance.md), and the next bounded roadmap in [`docs/next-session-roadmap.md`](docs/next-session-roadmap.md).

## License

MIT — see [LICENSE](LICENSE) file.
