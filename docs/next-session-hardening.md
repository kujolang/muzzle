# Muzzle: Next-Session Hardening Backlog

This backlog follows the August 2026 production-readiness review. Muzzle 1.0 is a strong, tested local workflow-compression tool, but it should not be presented as an enterprise isolation boundary. The items below are the highest-value ways to expand its production utility while preserving the stable trusted-local CLI contract.

## Repository Layout Decision

Keep `muzzle` and `muzzle.kujo` at the repository root. They are compatibility entrypoints, not duplicate implementation files: `muzzle` locates the runtime and delegates to `muzzle.kujo`, while the entrypoint imports the implementation modules from `src/`. Moving either file would break documented clone-and-run commands and existing PATH usage. The reusable implementation is already organized under `src/`; no root source file is currently redundant.

## Priority 0: Runtime Robustness

### 1. Bound memory while preserving complete logs

The current runner captures the complete combined workflow output in memory before writing the log. Very noisy or long-running workflows can therefore increase Muzzle's memory use substantially.

Acceptance criteria:

- Stream or spool stdout/stderr directly to the run log without truncating it.
- Retain only a bounded tail in memory for summaries and error excerpts.
- Preserve exit-code propagation, timeout behavior, `--json`, and full local logs.
- Add a deterministic large-output regression and record peak-memory evidence.

### 2. Terminate complete process trees on timeout and interruption

Prove that timeouts and user interrupts do not leave child or grandchild processes running.

Acceptance criteria:

- Define exit codes for timeout and interruption.
- Terminate the workflow process group with a bounded graceful-shutdown period and forced fallback.
- Write a valid failure report even when interrupted.
- Add Unix process-tree regressions and document platform limitations.

### 3. Add an opt-in executable safety policy

Manifest safety fields are currently descriptive. Add an explicit policy mode without silently changing the 1.0 default behavior.

Acceptance criteria:

- Add a flag or configuration mode that enforces `require_git_repo`, `allow_dirty_tree`, and approval requirements.
- Refuse network-marked or approval-marked workflows when the selected policy requires confirmation.
- Keep default trusted-local behavior backward compatible.
- Emit machine-readable policy-denial details.

## Priority 1: Enterprise Operations

### 4. Add `muzzle doctor` and strict manifest validation

Validate runtime discovery, directory boundaries, runner availability, manifests, required fields, argument metadata, and writable artifact paths without executing workflows.

Acceptance criteria:

- Human-readable and JSON output modes.
- Stable finding codes and nonzero exit status for errors.
- Detect malformed JSON separately from a missing optional manifest.
- Validate manifest name/script/runner/args/safety types consistently across `list`, `info`, and `run`.

### 5. Add bounded artifact retention

Long-lived projects need predictable disk use.

Acceptance criteria:

- Support dry-run cleanup by age, workflow, and retained-run count.
- Delete only recognized Muzzle log/report filename contracts.
- Preserve symlink and project-boundary protections.
- Return deletion counts and failures in JSON as well as text.

### 6. Standardize machine-readable command errors

Only successful and failed workflow runs currently have the full JSON report contract. Automation would benefit from JSON for validation errors and inspection commands.

Acceptance criteria:

- Define a versioned error envelope with code, message, command, and optional details.
- Add JSON modes for `list`, `info`, `logs`, `report`, `clean`, `loop`, and `doctor`.
- Keep stdout parseable and route diagnostics consistently.
- Add schema fixtures and exact contract tests.

### 7. Make manifest arguments operational

Argument metadata is currently documentation-only.

Acceptance criteria:

- Add opt-in validation for required arguments, arity, allowed values, and sensitive-value display rules.
- Ensure dry-run output redacts arguments marked sensitive.
- Preserve literal argument forwarding and the `--` delimiter contract.
- Document the compatibility strategy before enabling enforcement by default.

## Priority 2: Adoption and Proof

### 8. Add repeatable performance benchmarks

Measure startup time, output compression ratio, large-log throughput, concurrent-run behavior, and memory use. Store thresholds or comparison guidance without committing bulky generated output.

### 9. Improve installation and portability

Add a versioned installation path, shell completions, and CI coverage for supported macOS/Linux and Bash versions. Clearly document Windows support as unsupported or provide a native launcher strategy.

### 10. Add extensible runners without shell-string construction

Explore a structured process API in Kujo and a runner registry so future runtimes can be added without growing dispatch conditionals. Preserve literal argument boundaries and avoid `eval`-style execution.

### 11. Add integrity and provenance options

Offer optional workflow checksums, manifest/schema versions, and signed policy bundles for teams that need reviewable provenance. Keep the documentation explicit that integrity checks do not create a sandbox.

## Review Gate for the Next Session

Start with items 1 and 2 because they close the largest operational risks. Before implementation, verify the Kujo runtime's streaming/process-group APIs and write contract tests that capture current exit codes, JSON fields, and artifact paths. Finish with the full wrapper regression suite plus targeted performance and orphan-process checks.
