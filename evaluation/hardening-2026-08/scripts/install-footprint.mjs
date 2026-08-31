#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const [baselineArg, currentArg, outputArg] = process.argv.slice(2);
if (!baselineArg || !currentArg || !outputArg) {
  console.error("Usage: install-footprint.mjs <baseline-root> <current-root> <output.json>");
  process.exit(2);
}

function filesUnder(root) {
  const result = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const target = path.join(root, entry.name);
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) result.push(...filesUnder(target));
    else if (entry.isFile()) result.push(target);
  }
  return result;
}

function inspect(label, root) {
  const prefix = fs.mkdtempSync(path.join(os.tmpdir(), `muzzle-install-${label}-`));
  try {
    const result = spawnSync("bash", [path.join(root, "scripts", "install.sh"), "--prefix", prefix], { encoding: "utf8" });
    if (result.status !== 0) throw new Error(result.stderr || result.stdout);
    const files = filesUnder(prefix);
    return {
      fileCount: files.length,
      installedBytes: files.reduce((sum, file) => sum + fs.statSync(file).size, 0),
      files: files.map((file) => ({ path: path.relative(prefix, file), bytes: fs.statSync(file).size })).sort((a, b) => a.path.localeCompare(b.path)),
    };
  } finally {
    fs.rmSync(prefix, { recursive: true, force: true });
  }
}

const baseline = inspect("baseline", path.resolve(baselineArg));
const current = inspect("current", path.resolve(currentArg));
const output = path.resolve(outputArg);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify({
  schemaVersion: "muzzle.install-footprint/v1",
  baseline,
  current,
  change: { fileCount: current.fileCount - baseline.fileCount, installedBytes: current.installedBytes - baseline.installedBytes },
}, null, 2)}\n`);
