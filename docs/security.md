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

This prevents:
- Path traversal attacks (`../../etc/passwd`)
- Symlink escapes to outside directories
- Accidental execution of system binaries
- External writes or cleanup through symlinked artifact/state directories

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
- **Full logs** (`.muzzle/logs/`): All output preserved unchanged
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

Teams can checksum-pin scripts with `script_sha256`. They can also sign a `muzzle.policy/v1` JSON bundle using `scripts/sign-policy.sh` and pass its bundle, public key, and detached signature to `muzzle run`. A verified bundle authorizes only listed workflows and forces enforce mode. Key custody, issuer trust, rotation, and expiry policy belong to the operator.

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
