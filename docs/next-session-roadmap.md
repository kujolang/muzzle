# Muzzle: Next-Session Roadmap

This list begins after completion of the August 2026 hardening backlog. Muzzle is production-ready for trusted local workflow compression; these are bounded improvements, not release blockers.

## 1. Package and release automation

- Publish checksummed release archives containing the versioned layout and completions.
- Add an upgrade/uninstall command that never removes user `.muzzle/` projects.
- Pin the Kujo runtime revision and release toolchain for reproducible release gates (third-party actions are already commit-pinned).

## 2. Policy lifecycle

- Enforce optional policy-bundle expiry and issuer allowlists.
- Add key-rotation guidance and multi-signature support without storing private keys.
- Integrate an external approval provider behind an explicit adapter contract.

## 3. Runner plugins

- Replace the internal catalog with a validated project-local runner registry.
- Define executable discovery, version probes, file extensions, and capability metadata.
- Preserve structured argv execution and reject shell command strings.

## 4. Performance baselines

- Capture comparable Linux and macOS release-build baselines in CI artifacts.
- Add conservative regression thresholds after enough stable samples exist.
- Exercise sustained concurrent large-output workloads and slow log filesystems.

## 5. Platform reach

- Decide between WSL-only support and a native Windows launcher/process-tree implementation.
- Add architecture coverage for Linux arm64 and macOS Apple Silicon release artifacts.

## Review gate

Require `make quality`, schema contract tests, the process-tree suite, install/uninstall tests in an isolated prefix, and a benchmark comparison before release-related changes merge.
