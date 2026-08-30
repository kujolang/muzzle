# Muzzle: Security Model

## Trust Boundary

Muzzle is a **local workflow runner**. It executes scripts that exist on your filesystem.

### What Muzzle Trusts

- Scripts inside `.muzzle/workflows/` — you put them there
- The `.muzzle/manifests/` metadata — you write it
- Your local environment — same as running the script directly

### What Muzzle Does NOT Trust

- Scripts outside `.muzzle/workflows/` — rejected with error
- Network-downloaded scripts — Muzzle has no download capability
- User input as shell code — arguments are passed via `"$@"` array, never `eval`'d
- Environment variables in summaries — never printed in default output

## Argument Safety

Muzzle invokes its execution helper and supported runners with structured argument arrays, so every workflow argument remains a literal value.

This means:
- Arguments are individual strings, not concatenated into a command fragment
- Spaces, quotes, and shell metacharacters in arguments are preserved literally
- No shell injection is possible through Muzzle's argument passing

**Note**: The workflow script itself is responsible for safely handling its arguments. Muzzle cannot protect against a workflow script that uses `eval` on its inputs.

## Path Safety

Muzzle validates that workflow scripts are inside the expected directory:

1. Anchors `.muzzle/` to the current project rather than trusting a symlinked root
2. Resolves the workflow directory and script's real paths (following symlinks)
3. Rejects execution if either path escapes the project-local `.muzzle/` tree
4. Applies the same project-local boundary to log, report, manifest, session, and loop-state access
5. Copies the selected script into an owner-only execution snapshot and verifies that the snapshot digest matches the bytes validated before policy evaluation

This prevents:
- Path traversal attacks (`../../etc/passwd`)
- Symlink escapes to outside directories
- Accidental execution of system binaries
- External writes or cleanup through symlinked artifact/state directories
- Pathname replacement between integrity validation and interpreter startup

## Secret Redaction

Muzzle scans output for common secret patterns and redacts matching lines from **summaries only**. Single-line matching is case-insensitive.

### Patterns Detected

| Pattern | Example |
|---------|---------|
| `TOKEN=` | `export TOKEN=abc123` |
| `API_KEY=` | `API_KEY=sk-1234567890` |
| `SECRET=` | `SECRET=mysecret` |
| `PRIVATE_KEY` | `-----BEGIN PRIVATE KEY-----` |
| `Authorization:` | `Authorization: Bearer eyJ...` |
| `Bearer ` | `Bearer abc123` |
| `password=` | `password=hunter2` |
| `credential=` | `credential=admin:pass` |

### Redaction Behavior

- **Summaries** (default output): Matching lines replaced with `[REDACTED — secret pattern detected]`
- **Full logs** (`.muzzle/logs/`): All output preserved unchanged in Muzzle-owned mode-`0600` files on supported Unix systems
- **JSON reports**: Error excerpt field is redacted; summary field is your text
- **Verbose mode**: Terminal output is NOT redacted (you chose to see everything)

### Limitations

- Pattern-based detection is conservative and will miss obfuscated secrets
- Base64-encoded secrets are not detected
- Arbitrary secrets split across multiple lines are not detected unless they match one of the supported key/certificate block markers
- Custom secret formats are not detected

**Recommendation**: Never print secrets from workflow scripts. Use environment variables and reference them, don't echo them.

## Input Validation

Muzzle validates workflow names before execution:

- **Length**: 1–128 characters
- **Forbidden characters**: `/`, `\`, `..` (prevents path traversal)
- **Empty names**: Rejected

Workflow scripts are validated to reside under `.muzzle/workflows/` using realpath checks. Scripts outside this directory tree are rejected regardless of symlinks.

Workflow names supplied to `run`, `info`, `logs`, `report`, and loop commands use the same validation rules, so read-only inspection paths cannot bypass the project-local naming boundary.

## Timeout Protection

The `--timeout <ms>` flag bounds workflow execution time:

- **Default**: 300,000ms (5 minutes)
- **Minimum**: 1,000ms (1 second)
- **Maximum**: 3,600,000ms (1 hour)

Workflows exceeding the timeout are terminated. This prevents runaway processes from blocking agent workflows indefinitely.

On macOS and Linux, Kujo starts the helper in its own process group and terminates that group on timeout, cancellation-file detection, SIGINT, or SIGTERM. Muzzle uses exit 124 for timeout and 130 for cancellation/interruption, and writes a failure report for runtime cancellation paths. Native Windows process-tree behavior is not supported.

## Opt-In Policy and Provenance

The default `--policy trusted` mode preserves the 1.0 trusted-local contract. `--policy enforce` evaluates `require_git_repo`, `allow_dirty_tree`, `requires_network`, and `human_approval_recommended`; network- or approval-marked workflows require `--approve`. `--validate-args` separately enforces positional requirements, allowlists, arity, and dry-run redaction.

Teams can checksum-pin scripts with `script_sha256`. Whether pinned or unpinned, Muzzle passes the digest observed during validation to its execution helper. The helper creates a private snapshot, verifies that exact digest again, and executes only the snapshot. A mutation before snapshot completion is denied with exit 3; a later mutation cannot change the bytes already selected for execution. Bash, Python, and Node wrappers preserve the original script identity and normal sibling loading; Kujo runs the snapshot while retaining the project working directory.

Teams can also sign a `muzzle.policy/v1` JSON bundle using `scripts/sign-policy.sh` and pass its bundle, public key, and detached signature to `muzzle run`. A verified bundle authorizes only listed workflows and forces enforce mode. Key custody, issuer trust, rotation, and expiry policy belong to the operator.

The script digest covers the selected workflow file, not mutable helper modules, subprocesses, or other files it loads. Pin or otherwise control those dependencies separately when that distinction matters.

These checks establish integrity and reviewable authorization; they do not isolate a workflow or restrict its operating-system capabilities.

Muzzle does NOT:
- Print environment variables in default output
- Include `env` output in summaries or reports
- Log environment variables to report files

Workflow scripts inherit the caller's full environment. This is the same security model as running the script directly.

## File System Access

Muzzle writes to:
- `.muzzle/logs/` — workflow output capture
- `.muzzle/reports/` — markdown and JSON reports
- `.muzzle/state/` — session and loop state
- `.muzzle/state/executions/` — transient owner-only workflow snapshots, removed after normal completion, timeout, cancellation, or wrapper-forwarded interruption

Muzzle creates its log and report files with owner-only permissions (`0600`) and its transient execution state with owner-only directory permissions (`0700`) on supported Unix systems. Workflow scripts retain the caller's original umask, so this hardening does not change the permissions of files created by the workflow itself.

Muzzle does NOT write outside `.muzzle/` unless the workflow script does so.

## Network Access

Muzzle itself makes no network connections. Network access depends entirely on the workflow scripts you create.

Use the `safety.requires_network` manifest field to document which workflows need network access.

## Git Safety

Muzzle does NOT:
- Auto-commit changes
- Auto-push to remotes
- Modify git configuration
- Run destructive git commands

Any git operations are performed by your workflow scripts, not by Muzzle.

## Recommended Practices

1. **Review workflow scripts** before adding them to `.muzzle/workflows/`
2. **Use `safety.human_approval_recommended: true`** for dangerous workflows
3. **Add `.muzzle/logs/` and `.muzzle/reports/` to `.gitignore`** (Muzzle does this on `init`)
4. **Never echo secrets** in workflow scripts
5. **Use `--dry-run`** to preview workflows before first execution
6. **Keep Muzzle updated** as security improvements are released
7. **Trust but verify** — Muzzle provides guardrails, not a sandbox

## Out of Scope

- Workflow sandboxing or operating-system capability isolation
- Automatic key distribution, certificate authority, or remote approval service
- Native Windows process management
- Isolation from another process running as the same operating-system user
