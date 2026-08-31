#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const args = Object.fromEntries(process.argv.slice(2).map((value, index, all) => {
  if (!value.startsWith("--")) return ["", ""];
  const next = all[index + 1];
  return [value.slice(2), next && !next.startsWith("--") ? next : "true"];
}).filter(([key]) => key));

const required = ["baseline", "current", "kujo-bin", "kujo-modules", "output"];
for (const key of required) {
  if (!args[key]) {
    console.error(`Missing --${key}`);
    process.exit(2);
  }
}

const baselineRoot = path.resolve(args.baseline);
const currentRoot = path.resolve(args.current);
const kujoBin = path.resolve(args["kujo-bin"]);
const kujoModules = path.resolve(args["kujo-modules"]);
const outputPath = path.resolve(args.output);
const warmups = Number(args.warmups ?? 3);
const measuredRuns = Number(args.runs ?? 10);
const maximumLoad = Number(args["max-load"] ?? 12);
const initialLoad = os.loadavg()[0];

if (!Number.isInteger(warmups) || warmups < 0 || !Number.isInteger(measuredRuns) || measuredRuns < 10) {
  console.error("--warmups must be non-negative and --runs must be an integer >= 10");
  process.exit(2);
}
if (initialLoad > maximumLoad) {
  console.error(`Refusing benchmark: 1-minute load average ${initialLoad.toFixed(2)} exceeds ${maximumLoad}`);
  process.exit(3);
}

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "muzzle-hardening-eval-"));
const states = new Map();
const commonEnv = {
  ...process.env,
  KUJO_BIN: kujoBin,
  KUJO_MODULE_PATH: kujoModules,
  LC_ALL: "C",
  LANG: "C",
  TZ: "UTC",
};

function runDirect(command, commandArgs, options = {}) {
  return spawnSync(command, commandArgs, {
    cwd: options.cwd,
    env: options.env ?? commonEnv,
    encoding: "utf8",
    maxBuffer: 32 * 1024 * 1024,
  });
}

function writeOutputWorkflow(target, lines, exitCode = 0) {
  fs.writeFileSync(target, `#!/usr/bin/env bash\nset -euo pipefail\nfor idx in $(seq 1 ${lines}); do\n  printf 'muzzle-eval-%08d-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz\\n' "$idx"\ndone\nexit ${exitCode}\n`);
  fs.chmodSync(target, 0o755);
}

function writeSizedWorkflow(target, requestedBytes) {
  const prefix = "#!/usr/bin/env bash\nset -euo pipefail\nprintf 'sized-workflow-ok\\n'\n";
  const remaining = Math.max(0, requestedBytes - Buffer.byteLength(prefix));
  let padding = "";
  if (remaining > 0) {
    padding = `#${"x".repeat(Math.max(0, remaining - 2))}\n`;
  }
  fs.writeFileSync(target, prefix + padding);
  fs.chmodSync(target, 0o755);
}

function prepare(label, root) {
  const project = path.join(tempRoot, label);
  fs.mkdirSync(project);
  const muzzle = path.join(root, "muzzle");
  const init = runDirect(muzzle, ["init"], { cwd: project });
  if (init.status !== 0) throw new Error(`${label} init failed: ${init.stderr || init.stdout}`);
  const workflows = path.join(project, ".muzzle", "workflows");
  for (const lines of [10, 100, 1000, 10000, 50000]) {
    writeOutputWorkflow(path.join(workflows, `output-${lines}.sh`), lines);
  }
  writeOutputWorkflow(path.join(workflows, "failure-5000.sh"), 5000, 7);
  for (const bytes of [1024, 65536, 1048576, 4194304, 16777216]) {
    writeSizedWorkflow(path.join(workflows, `script-${bytes}.sh`), bytes);
  }
  const state = { label, root, muzzle, project };
  states.set(label, state);
  return state;
}

function fileMode(file) {
  return (fs.statSync(file).mode & 0o777).toString(8).padStart(3, "0");
}

function parseTime(stderr) {
  const user = stderr.match(/^\s*([0-9.]+) real\s+([0-9.]+) user\s+([0-9.]+) sys/m);
  const rss = stderr.match(/^\s*(\d+)\s+maximum resident set size/m);
  return {
    timeRealMs: user ? Number(user[1]) * 1000 : null,
    userMs: user ? Number(user[2]) * 1000 : null,
    sysMs: user ? Number(user[3]) * 1000 : null,
    peakRssBytes: rss ? Number(rss[1]) : null,
  };
}

function measure(state, workload, sample, phase, sequence) {
  const commandArgs = workload.kind === "startup"
    ? ["--version"]
    : ["run", workload.workflow, "--json"];
  const timedArgs = ["-l", "env", `KUJO_BIN=${kujoBin}`, `KUJO_MODULE_PATH=${kujoModules}`, "LC_ALL=C", "LANG=C", "TZ=UTC", state.muzzle, ...commandArgs];
  const started = process.hrtime.bigint();
  const result = runDirect("/usr/bin/time", timedArgs, { cwd: state.project, env: commonEnv });
  const wallMs = Number(process.hrtime.bigint() - started) / 1e6;
  const timing = parseTime(result.stderr ?? "");
  const expectedExit = workload.expectedExit ?? 0;
  const record = {
    label: state.label,
    workload: workload.name,
    category: workload.category,
    phase,
    sample,
    sequence,
    expectedExit,
    exitCode: result.status,
    success: result.status === expectedExit,
    wallMs,
    ...timing,
    stdoutBytes: Buffer.byteLength(result.stdout ?? ""),
    stdoutLines: (result.stdout ?? "").split("\n").filter(Boolean).length,
    load1: os.loadavg()[0],
  };
  if (workload.kind !== "startup") {
    try {
      const summary = JSON.parse(result.stdout);
      const log = path.resolve(state.project, summary.log_path);
      const report = path.resolve(state.project, summary.report_path);
      const reportJson = report.replace(/\.md$/, ".json");
      record.logBytes = fs.statSync(log).size;
      record.logMode = fileMode(log);
      record.reportMode = fileMode(report);
      record.jsonReportMode = fileMode(reportJson);
      record.schemaVersion = summary.schema_version ?? null;
      record.command = summary.command ?? null;
      record.displayTruncated = summary.display_truncated;
      record.reportedDurationMs = summary.duration_ms;
    } catch (error) {
      record.parseError = String(error);
    }
  }
  return record;
}

const allWorkloads = [
  { name: "startup", category: "minimal", kind: "startup", runs: 15 },
  { name: "output-10", category: "minimal", workflow: "output-10" },
  { name: "output-100", category: "typical", workflow: "output-100" },
  { name: "output-1000", category: "scaling", workflow: "output-1000" },
  { name: "output-10000", category: "large", workflow: "output-10000" },
  { name: "output-50000", category: "stress-agent", workflow: "output-50000" },
  { name: "failure-5000", category: "failure", workflow: "failure-5000", expectedExit: 7 },
  { name: "script-1024", category: "script-scaling", workflow: "script-1024" },
  { name: "script-65536", category: "script-scaling", workflow: "script-65536" },
  { name: "script-1048576", category: "script-scaling", workflow: "script-1048576" },
  { name: "script-4194304", category: "script-scaling", workflow: "script-4194304" },
  { name: "script-16777216", category: "script-scaling", workflow: "script-16777216" },
];
const selectedNames = args.workloads ? new Set(args.workloads.split(",")) : null;
const workloads = selectedNames ? allWorkloads.filter((workload) => selectedNames.has(workload.name)) : allWorkloads;
if (workloads.length === 0) {
  console.error("--workloads did not match a defined workload");
  process.exit(2);
}

try {
  prepare("baseline", baselineRoot);
  prepare("current", currentRoot);
  const records = [];
  let sequence = 0;
  for (const workload of workloads) {
    const runs = workload.runs ?? measuredRuns;
    for (const phase of ["warmup", "measured"]) {
      const count = phase === "warmup" ? warmups : runs;
      for (let sample = 1; sample <= count; sample += 1) {
        const labels = sample % 2 === 1 ? ["baseline", "current"] : ["current", "baseline"];
        for (const label of labels) {
          sequence += 1;
          records.push(measure(states.get(label), workload, sample, phase, sequence));
        }
      }
    }
  }
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify({
    schemaVersion: "muzzle.hardening-benchmark.raw/v1",
    generatedAt: new Date().toISOString(),
    configuration: { warmups, measuredRuns, initialLoad, maximumLoad, kujoBin, kujoModules },
    checkouts: { baseline: baselineRoot, current: currentRoot },
    workloads,
    records,
  }, null, 2)}\n`);
  const failures = records.filter((record) => !record.success || record.parseError);
  if (failures.length > 0) {
    console.error(`Benchmark completed with ${failures.length} invalid samples`);
    process.exitCode = 1;
  }
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
