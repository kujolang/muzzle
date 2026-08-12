# Changelog

All notable changes to Muzzle are documented here.

## Unreleased

- Restore the documented `muzzle version` command path.
- Align README version badge with `kennel.toml` and CLI output.
- Add deterministic Eval suite for prelaunch review evidence.
- Reject symlinked or non-directory Muzzle roots that escape project-local workflow, artifact, or loop-state boundaries.
- Report invalid numeric options, malformed manifest/session/loop state, invalid loop transitions, and cleanup failures without raw runtime crashes or false success.
- Escape free-form loop notes so `muzzle loop summary` remains a valid one-row-per-iteration Markdown table.

## [1.0.0] - 2026-08-08

- Declared the trusted-local CLI, manifest, compact-summary, logging, reporting, and loop contracts stable.
- Aligned the launcher, runtime, manifest, Spec, and README at 1.0.0.

## [0.2.0] - 2026-06-27

- Prepared Muzzle for public release with quiet workflow execution, manifest-backed workflow metadata, loop tracking, compact JSON summaries, and wrapper regression coverage.
