# Muzzle: Agent Usage Guide

## Why Agents Should Use Muzzle

AI coding agents waste significant context window space on operational noise:

- **Build output**: Hundreds of lines of compiler/bundler output
- **Deploy output**: Full JSON responses from deployment APIs
- **Test output**: Thousands of lines of test runner output
- **Git output**: Verbose push/fetch/status output
- **Repeated instructions**: The same "run build, check tests, deploy" prompts

Muzzle compresses this noise in the reviewed workflows. The agent often sees a short summary instead of hundreds of lines of raw output.

## How to Use Muzzle as an Agent

### Basic Pattern

Instead of:
```
Run: npm run build && npm test && git push origin main
[agent dumps all output into context]
```

Use:
```
muzzle run build-and-test
muzzle run push-current
```

The agent gets compact summaries and can read full logs only when needed.

### Reading Logs on Failure

When a workflow fails, Muzzle prints a short error excerpt. If the agent needs more context:

```
muzzle logs build-and-test
cat .muzzle/logs/build-and-test-2026-05-28T150000.log
```

### JSON Mode for Programmatic Consumption

```
muzzle run deploy production --json
```

Returns:
```json
{
  "workflow": "deploy",
  "status": "success",
  "exit_code": 0,
  "duration_ms": 18420,
  "log_path": ".muzzle/logs/deploy-2026-05-28T150000.log",
  "report_path": ".muzzle/reports/deploy-2026-05-28T150000.md",
  "summary": "The workflow completed successfully.",
  "error_excerpt": null
}
```

### Loop Mode for Multi-Step Tasks

When the user asks for repeated iterations:

```
muzzle loop start release-hardening --limit 10

# For each iteration:
muzzle loop next
# [agent does the work]
muzzle loop done --note "Fixed README commands against CLI help"

# Check progress:
muzzle loop status
```

### Dry Run Before Execution

```
muzzle run deploy production --dry-run
```

Safely previews what would happen without executing.

## Token Savings (Estimates)

| Scenario | Without Muzzle | With Muzzle | Approximate Savings |
|----------|---------------|-------------|-------------------|
| npm build (200 lines output) | ~200 lines in context | 6 lines summary | ~97% |
| Deploy with JSON response | ~50 lines | 6 lines summary | ~88% |
| Test suite (500 lines) | ~500 lines | 6-12 lines | ~97% |
| Git push output | ~15 lines | 6 lines | ~60% |
| 10-iteration loop instructions | Repeated prompt each time | Loop state tracking | ~90% prompt reuse |

*Estimates are approximate. Actual savings depend on workflow output volume.*

## Safety for Agents

- Muzzle only runs scripts from `.muzzle/workflows/`; it rejects other paths
- Dry-run mode lets agents preview before executing
- Secret redaction prevents accidental token leakage into context
- Safety flags in manifests help agents identify dangerous workflows
- Muzzle itself sends nothing to external services; any network access comes from the workflow scripts you create

## Recommended Agent Prompt Pattern

When instructing an agent to use Muzzle:

```
Use `muzzle run <workflow>` for known workflows instead of running commands directly.
Check `muzzle list` for available workflows.
Use `--json` for programmatic output.
Use `--dry-run` to preview dangerous workflows.
Use `--timeout <ms>` for long-running tasks.
Read logs with `cat .muzzle/logs/<file>` only when investigation is needed.
```

## Integration with Other Tools

### With Dispatch
Dispatch can call Muzzle as a workflow step:
```yaml
steps:
  - name: build
    command: muzzle run build-check --json
```

### With MCP (Future)
Planned MCP tools may expose `muzzle_run`, `muzzle_list`, and `muzzle_logs` directly to agents.

### With Leash (Future)
Dangerous workflows (marked `human_approval_recommended: true`) will pause for mobile approval via Leash.
