# Compare Agent Context With And Without Muzzle

This guide shows how to ask Codex or another local coding agent to run the same real task twice:

1. A raw baseline where noisy commands run directly.
2. A Muzzle run where the agent uses `muzzle run <workflow>` for noisy commands.

Use this when you want to see whether Muzzle preserves agent context during a normal build, test, debug, and verification loop.

## What You Can Measure

Muzzle does not change the prompt sent to a model and does not know the model provider's token bill. Muzzle changes what local command output is exposed back into the agent transcript.

Track these separately:

| Metric | Source | Meaning |
|---|---|---|
| Agent input/output tokens | Codex or agent usage summary, when available | Actual model usage for the full session. |
| Context window usage | Codex or agent UI, when available | How full the agent conversation became. |
| Provider tokens from app/API calls | SDK response usage, Watchdog, or RunLedger notes | Tokens used by model calls made inside the task. |
| Exposed local transcript bytes/tokens | Saved raw command output vs saved Muzzle summaries | Approximate context consumed by local command output. |
| Wall-clock and exit status | Muzzle JSON reports or shell timing | Whether Muzzle changed task ergonomics or outcomes. |

The most important comparison is usually local transcript exposure. Provider token usage for the main task may stay similar, while the agent's visible terminal output becomes much smaller.

## Use A Clean Experiment Shape

For a fair comparison:

- Use the same repo, task prompt, model, agent, and starting commit for both runs.
- Start each run in a fresh agent session so the raw run does not pollute the Muzzle run.
- Use two branches or two worktrees from the same base commit.
- Ask the agent to do the whole task normally, including investigation, edits, tests, and handoff.
- Ask the agent to report final usage/context numbers from its UI if the agent exposes them.

Example worktree setup:

```bash
cd /path/to/project
git status --short
git rev-parse HEAD

git worktree add ../project-raw HEAD
git worktree add ../project-muzzle HEAD
```

## Add Real Muzzle Workflows To The Target Repo

In the Muzzle worktree, initialize Muzzle and add workflows for the commands your agent normally repeats. Do this in the target project, not in the Muzzle repo.

```bash
cd ../project-muzzle
muzzle init

cat > .muzzle/workflows/project-verify.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

section() {
  printf '\n== %s ==\n' "$1"
}

if [ -f package.json ]; then
  if [ ! -d node_modules ]; then
    echo "node_modules is missing. Install dependencies before benchmarking."
    exit 2
  fi

  section "lint/test/build"
  npm run format:check --if-present
  npm run lint --if-present
  npm test -- --watch=false
  npm run build --if-present
elif [ -f composer.json ]; then
  section "composer validate"
  composer validate

  section "php tests"
  if [ -x vendor/bin/phpunit ]; then
    vendor/bin/phpunit
  else
    find . -path './vendor' -prune -o -name '*.php' -print0 | xargs -0 -n1 php -l
  fi
elif [ -f Makefile ]; then
  section "make"
  make
else
  section "fallback"
  git status --short
fi
EOF
chmod +x .muzzle/workflows/project-verify.sh

cat > .muzzle/manifests/project-verify.json <<'EOF'
{
  "name": "project-verify",
  "summary": "Run the project's normal verification commands.",
  "runner": "bash",
  "script": "workflows/project-verify.sh",
  "args": [],
  "quiet_by_default": true,
  "safety": {
    "require_git_repo": true,
    "allow_dirty_tree": true,
    "requires_network": false,
    "human_approval_recommended": false
  }
}
EOF
```

Edit `project-verify.sh` to use the real commands for the project. For a real feature task, this workflow should be the same lint/test/build command set you would expect the agent to run several times.

Check it before giving the task to the agent:

```bash
muzzle list
muzzle info project-verify
muzzle run project-verify --dry-run
```

## Optional: Use The Feature Card Workflow

If you want a heavier real-world run, use the feature-card workflow from the sibling workflows repo. It drives a card through context, implementation, verification, proof, summaries, ledger, and handoff.

From the target repo:

```bash
mkdir -p .muzzle/workflows .muzzle/manifests
cp /Users/robertdevore/2026/Kujolang/kujo-repos/kujo-workflows/feature-card-workflow/muzzle-template/workflows/feature-card-full.sh .muzzle/workflows/
cp /Users/robertdevore/2026/Kujolang/kujo-repos/kujo-workflows/feature-card-workflow/muzzle-template/manifests/feature-card-full.json .muzzle/manifests/
chmod +x .muzzle/workflows/feature-card-full.sh

FEATURE_VERIFY_COMMANDS=$'npm test -- --watch=false\nnpm run build' \
muzzle run feature-card-full CARD-123 card.md /path/to/project
```

Use this when the task already fits a card-driven workflow. For a simpler product feature, the `project-verify` workflow is usually easier to control.

## Prompt 1: Raw Baseline Agent Run

Start a fresh agent session in `../project-raw` and give it this prompt, adapted to your task:

```text
You are running the raw baseline for a Muzzle context comparison.

Do not use Muzzle in this session.

Task:
<paste the real project task here>

Measurement rules:
- Work normally: inspect files, edit code, and run the verification commands you would usually run.
- Run noisy verification commands directly, not through Muzzle.
- When running verification commands, pipe through tee so the output is both visible in the transcript and saved under .muzzle-measure/raw/.
- Use the same verification command set that the Muzzle run will use.
- At the end, report any available agent usage numbers: input tokens, output tokens, context used, context remaining, and compaction events.
- Also report files changed, commands run, tests passed/failed, and remaining risks.

For repeated verification, use commands like:
mkdir -p .muzzle-measure/raw
npm test -- --watch=false 2>&1 | tee .muzzle-measure/raw/npm-test-01.log
npm run build 2>&1 | tee .muzzle-measure/raw/npm-build-01.log
```

The `tee` logs let you estimate how much local command output was exposed to the agent.

## Prompt 2: Muzzle Agent Run

Start a new fresh agent session in `../project-muzzle` from the same base commit and give it the same task:

```text
You are running the Muzzle side of a context comparison.

Use Muzzle for noisy local workflows.

Task:
<paste the same real project task here>

Measurement rules:
- Work normally: inspect files, edit code, and run verification as needed.
- Before running project verification, check `muzzle list` and `muzzle info project-verify`.
- Use `muzzle run project-verify --json` instead of running the raw verification commands directly.
- Save each Muzzle command summary under .muzzle-measure/muzzle/ with tee.
- Read full Muzzle logs only when a workflow fails or when the error excerpt is not enough.
- At the end, report any available agent usage numbers: input tokens, output tokens, context used, context remaining, and compaction events.
- Also report files changed, commands run, tests passed/failed, and remaining risks.

For repeated verification, use commands like:
mkdir -p .muzzle-measure/muzzle
muzzle run project-verify --json 2>&1 | tee .muzzle-measure/muzzle/project-verify-01.json
```

This run should perform the same real task. The difference is that full command output lands in `.muzzle/logs/`, while the agent sees only the compact summary unless it needs to inspect a failure.

## Compare Exposed Command Output

After both runs finish, estimate exposed local transcript size from the saved outputs:

```bash
cd /path/to/project-raw
python3 - <<'PY'
from pathlib import Path
import math

def total_bytes(root):
    p = Path(root)
    return sum(f.stat().st_size for f in p.glob("**/*") if f.is_file())

raw = total_bytes(".muzzle-measure/raw")
print(f"raw_bytes={raw}")
print(f"raw_estimated_tokens={math.ceil(raw / 4) if raw else 0}")
PY

cd /path/to/project-muzzle
python3 - <<'PY'
from pathlib import Path
import math

def total_bytes(root):
    p = Path(root)
    return sum(f.stat().st_size for f in p.glob("**/*") if f.is_file())

muzzle = total_bytes(".muzzle-measure/muzzle")
logs = total_bytes(".muzzle/logs")
print(f"muzzle_visible_bytes={muzzle}")
print(f"muzzle_visible_estimated_tokens={math.ceil(muzzle / 4) if muzzle else 0}")
print(f"muzzle_full_log_bytes_on_disk={logs}")
PY
```

The `/ 4` token estimate is intentionally rough. It is good enough for comparing command-output exposure between two runs; use actual agent usage numbers when the agent provides them.

## Compare Final Results

Create a small comparison table:

```markdown
| Metric | Raw | Muzzle | Notes |
|---|---:|---:|---|
| Agent input tokens |  |  | From agent usage summary, if available. |
| Agent output tokens |  |  | From agent usage summary, if available. |
| Context used |  |  | From agent UI, if available. |
| Compactions |  |  | Count any context compaction events. |
| Visible command-output bytes |  |  | `.muzzle-measure/raw` vs `.muzzle-measure/muzzle`. |
| Estimated visible command-output tokens |  |  | Bytes / 4. |
| Full logs retained on disk | n/a |  | `.muzzle/logs` total bytes. |
| Verification pass/fail |  |  | Same expected command set. |
| Files changed |  |  | Compare `git diff --stat`. |
| Wall-clock time |  |  | Optional. |
```

Interpret the result this way:

- If provider tokens are similar, Muzzle did not materially change the model request.
- If visible command-output tokens are much lower, Muzzle preserved context during local verification.
- If the Muzzle run needed to inspect full logs repeatedly, improve the workflow's failure output or split the workflow into smaller steps.
- If the raw run compacted and the Muzzle run did not, that is the clearest practical win.

## Optional: Record The Comparison In RunLedger

If RunLedger is available, use it as the audit record and copy the final agent usage numbers into it manually:

```bash
runledger start --provider codex --model "<model>" --task "Muzzle context comparison" --repo /path/to/project-raw
runledger usage <raw-run-id> --input <input_tokens> --output <output_tokens>
runledger finish <raw-run-id> --status pass --verdict "Raw baseline completed."

runledger start --provider codex --model "<model>" --task "Muzzle context comparison" --repo /path/to/project-muzzle
runledger usage <muzzle-run-id> --input <input_tokens> --output <output_tokens>
runledger finish <muzzle-run-id> --status pass --verdict "Muzzle run completed."
```

RunLedger records the receipt. Muzzle records the workflow logs and reports. The agent or UI remains the source of truth for whole-session token and context usage.

## Prior Benchmark Workflow

The sibling workflow at `/Users/robertdevore/2026/Kujolang/kujo-repos/kujo-workflows/ai-sdk-muzzle-benchmark/` already implements the same comparison pattern for repeated AI SDK app-generation trials:

- `raw`: run AI SDK request and verification directly.
- `muzzle`: run noisy local stages through Muzzle.
- Compare provider token usage separately from local transcript exposure.

Use that workflow for repeatable model/API benchmarking. Use this guide when you want to compare a normal local coding session on a real project task.
