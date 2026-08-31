#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const args = Object.fromEntries(process.argv.slice(2).map((value, index, all) => value.startsWith("--")
  ? [value.slice(2), all[index + 1] && !all[index + 1].startsWith("--") ? all[index + 1] : "true"]
  : ["", ""]).filter(([key]) => key));
for (const key of ["baseline", "current", "kujo-bin", "output"]) {
  if (!args[key]) { console.error(`Missing --${key}`); process.exit(2); }
}

const warmups = Number(args.warmups ?? 3);
const runs = Number(args.runs ?? 15);
const maximumLoad = Number(args["max-load"] ?? 12);
const initialLoad = os.loadavg()[0];
if (runs < 10 || warmups < 0) { console.error("Use at least 10 measured runs"); process.exit(2); }
if (initialLoad > maximumLoad) { console.error(`Refusing benchmark at load ${initialLoad.toFixed(2)}`); process.exit(3); }

const roots = { baseline: path.resolve(args.baseline), current: path.resolve(args.current) };
const kujoBin = path.resolve(args["kujo-bin"]);
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "muzzle-helper-benchmark-"));
const records = [];
let sequence = 0;

function parseTime(stderr) {
  const cpu = stderr.match(/^\s*([0-9.]+) real\s+([0-9.]+) user\s+([0-9.]+) sys/m);
  const rss = stderr.match(/^\s*(\d+)\s+maximum resident set size/m);
  return { userMs: cpu ? Number(cpu[2]) * 1000 : null, sysMs: cpu ? Number(cpu[3]) * 1000 : null, peakRssBytes: rss ? Number(rss[1]) : null };
}

function makeWorkflow(file, bytes) {
  const prefix = "#!/usr/bin/env bash\nset -euo pipefail\nprintf 'helper-ok\\n'\n";
  fs.writeFileSync(file, prefix + `#${"x".repeat(Math.max(0, bytes - Buffer.byteLength(prefix) - 2))}\n`);
}

function prepare(label) {
  const project = path.join(tempRoot, label);
  fs.mkdirSync(path.join(project, ".muzzle", "workflows"), { recursive: true });
  fs.mkdirSync(path.join(project, ".muzzle", "logs"), { recursive: true });
  fs.mkdirSync(path.join(project, ".muzzle", "state"), { recursive: true });
  for (const bytes of [1024, 65536, 1048576, 4194304, 16777216]) makeWorkflow(path.join(project, ".muzzle", "workflows", `script-${bytes}.sh`), bytes);
  return project;
}

const projects = { baseline: prepare("baseline"), current: prepare("current") };
function measure(label, bytes, phase, sample) {
  const project = projects[label];
  const relativeScript = `.muzzle/workflows/script-${bytes}.sh`;
  const script = path.join(project, relativeScript);
  const digest = crypto.createHash("sha256").update(fs.readFileSync(script)).digest("hex");
  const log = `.muzzle/logs/${label}-${bytes}-${phase}-${sample}.log`;
  const helper = path.join(roots[label], "src", "muzzle_exec.sh");
  const helperArgs = label === "baseline"
    ? [helper, "bash", relativeScript, log, "false", kujoBin, "--"]
    : [helper, "bash", relativeScript, digest, `.muzzle/state/executions/${crypto.randomBytes(16).toString("hex")}`, log, "false", kujoBin, "--"];
  const started = process.hrtime.bigint();
  const result = spawnSync("/usr/bin/time", ["-l", "bash", ...helperArgs], { cwd: project, encoding: "utf8", maxBuffer: 1024 * 1024 });
  const wallMs = Number(process.hrtime.bigint() - started) / 1e6;
  sequence += 1;
  records.push({ label, workload: `script-${bytes}`, bytes, phase, sample, sequence, wallMs, ...parseTime(result.stderr), exitCode: result.status, success: result.status === 0, load1: os.loadavg()[0], logBytes: fs.statSync(path.join(project, log)).size });
}

try {
  for (const bytes of [1024, 65536, 1048576, 4194304, 16777216]) {
    for (const phase of ["warmup", "measured"]) {
      const count = phase === "warmup" ? warmups : runs;
      for (let sample = 1; sample <= count; sample += 1) {
        const labels = sample % 2 ? ["baseline", "current"] : ["current", "baseline"];
        for (const label of labels) measure(label, bytes, phase, sample);
      }
    }
  }
  const output = path.resolve(args.output);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, `${JSON.stringify({ schemaVersion: "muzzle.helper-benchmark.raw/v1", generatedAt: new Date().toISOString(), configuration: { warmups, runs, maximumLoad, initialLoad }, records }, null, 2)}\n`);
  if (records.some((record) => !record.success)) process.exitCode = 1;
} finally {
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
