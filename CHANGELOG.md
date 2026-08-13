# Changelog

All notable changes to Muzzle are documented here.

## Unreleased

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

## [1.0.0] - 2026-08-08

- Declared the trusted-local CLI, manifest, compact-summary, logging, reporting, and loop contracts stable.
- Aligned the launcher, runtime, manifest, Spec, and README at 1.0.0.

## [0.2.0] - 2026-06-27

- Prepared Muzzle for public release with quiet workflow execution, manifest-backed workflow metadata, loop tracking, compact JSON summaries, and wrapper regression coverage.
