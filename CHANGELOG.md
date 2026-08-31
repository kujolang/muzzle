# Changelog

All notable changes to Muzzle are documented here.

## Unreleased

- Add a reproducible before/after hardening evaluation with matched Kujo Eval outcomes, paired runtime distributions, raw evidence, a machine-readable receipt, and a public technical case study.

## [1.1.0] - 2026-08-30

- Spool full workflow output to disk with bounded in-process capture and explicit terminal truncation metadata.
- Terminate Unix workflow process groups on timeout, cancel-file requests, and forwarded interruption; standardize exits 124 and 130.
- Add strict manifest schemas, operational argument validation, enforce-mode safety policy, script checksum pins, and signed policy bundles.
- Add versioned JSON command/error contracts, `doctor`, `integrity`, and bounded artifact-retention commands.
- Add a versioned installer, Bash/Zsh completions, pinned Linux/macOS CI, repeatable performance signals, and process/install regressions.
- Restore the documented `muzzle version` command path.
- Align README version badge with `kennel.toml` and CLI output.
- Add deterministic Eval suite for prelaunch review evidence.
- Reject symlinked or non-directory Muzzle roots that escape project-local workflow, artifact, or loop-state boundaries.
- Report invalid numeric options, malformed manifest/session/loop state, invalid loop transitions, and cleanup failures without raw runtime crashes or false success.
- Serialize concurrent session-counter updates so successful parallel runs are not lost.
- Escape free-form loop notes so `muzzle loop summary` remains a valid one-row-per-iteration Markdown table.
- Sort workflow, loop, log, and report discovery for deterministic output across filesystems.
- Apply workflow-name validation consistently to inspection commands and reject malformed safety metadata cleanly.
- Include redacted failure excerpts in Markdown reports and correct stale output/version documentation.
- Add a canonical local quality gate and a copyable manifest-backed build-check example.
- Create logs and reports with owner-only permissions and bind signed-policy parsing to the bytes verified by OpenSSL.
- Bind validated workflow bytes to digest-verified private execution snapshots while preserving supported runner identity and import behavior.
- Pin the Kujo CI revision, reject unsafe forced-install paths, and publish the additive `muzzle.run/v1` JSON Schema contract.

## [1.0.0] - 2026-08-08

- Declared the trusted-local CLI, manifest, compact-summary, logging, reporting, and loop contracts stable.
- Aligned the launcher, runtime, manifest, Spec, and README at 1.0.0.

## [0.2.0] - 2026-06-27

- Prepared Muzzle for public release with quiet workflow execution, manifest-backed workflow metadata, loop tracking, compact JSON summaries, and wrapper regression coverage.
