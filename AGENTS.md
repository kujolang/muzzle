# Agent Notes

Muzzle is a Kujo-native CLI for reducing agent-visible workflow noise. Preserve CLI behavior and output contracts unless the task explicitly asks to change them.

## Canonical Reading Order

1. `README.md`
2. `docs/agent-usage.md`
3. `docs/howto.md`
4. `docs/workflows.md`
5. `docs/security.md`
6. `muzzle.kujo`, then `src/*.kujo`
7. `tests/muzzle_wrapper_regression.sh`

Prioritize copyable examples over tests: examples should model the most token-efficient idioms we want agents to imitate.

## Search Hygiene

Use `rg`/`rg --files` and exclude bulk or local-output paths during broad sweeps:

```bash
rg "pattern" -g '!/.dogfood/**' -g '!/.muzzle/**' -g '!/.kujo_cache/**'
```

Exclude generated/bulk paths from the main sweep unless the task explicitly targets them; document the search exclusions you used.

## Canonical vs Historical Material

- Canonical user-facing examples live in `README.md` and `docs/`.
- CLI behavior is covered by `tests/muzzle_wrapper_regression.sh`; keep exact-output checks targeted and intentional.
- `.dogfood/` contains historical project notes, copied specs, and validation logs. Treat it as legacy context, not canonical onboarding or examples, unless a task specifically targets dogfood artifacts.
- `.muzzle/logs/`, `.muzzle/reports/`, `.muzzle/state/`, and `.kujo_cache/` are generated/local output and should stay out of broad readability edits.

## Example Style

- Keep first examples direct and runnable.
- For longer Kujo examples, prefer local helpers such as `print_lines(lines)`, `section(title)`, or `kv(label, value)` when they reduce repeated `print(...)` without hiding the feature being demonstrated.
- For Bash examples, prefer loops for static step lists, sections, or repeated report lines.
- Include expected output where it helps agents verify the command quickly.
