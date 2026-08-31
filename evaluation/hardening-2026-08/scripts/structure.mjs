#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const [baselineArg, currentArg, outputArg] = process.argv.slice(2);
if (!baselineArg || !currentArg || !outputArg) {
  console.error("Usage: structure.mjs <baseline-root> <current-root> <output.json>");
  process.exit(2);
}

const excludedPrefixes = [".dogfood/", ".muzzle/", ".kujo_cache/"];
const codeExtensions = new Set([".kujo", ".sh"]);
const docExtensions = new Set([".md"]);

function git(root, args) {
  const result = spawnSync("git", ["-C", root, ...args], { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (result.status !== 0) throw new Error(result.stderr);
  return result.stdout;
}

function nonblankLines(content) {
  return content.split("\n").filter((line) => line.trim() !== "").length;
}

function inspect(root) {
  const files = git(root, ["ls-files", "-z"]).split("\0").filter(Boolean)
    .filter((file) => !excludedPrefixes.some((prefix) => file.startsWith(prefix)));
  const records = files.map((file) => {
    const content = fs.readFileSync(path.join(root, file), "utf8");
    return { file, bytes: Buffer.byteLength(content), lines: nonblankLines(content), content };
  });
  const source = records.filter((record) => codeExtensions.has(path.extname(record.file)) && !record.file.startsWith("tests/") && !record.file.startsWith("examples/"));
  const tests = records.filter((record) => record.file.startsWith("tests/") && codeExtensions.has(path.extname(record.file)));
  const docs = records.filter((record) => docExtensions.has(path.extname(record.file)));
  const functionPattern = /^\s*(?:export\s+)?func\s+[A-Za-z_][A-Za-z0-9_]*|^\s*[A-Za-z_][A-Za-z0-9_]*\(\)\s*\{/gm;
  const branchPattern = /\b(?:if|else if|while|for|case|except)\b/g;
  const todoPattern = /\b(?:TODO|FIXME)\b/g;
  const countMatches = (list, pattern) => list.reduce((total, record) => total + (record.content.match(pattern) ?? []).length, 0);
  return {
    sha: git(root, ["rev-parse", "HEAD"]).trim(),
    trackedFiles: records.length,
    trackedBytes: records.reduce((sum, record) => sum + record.bytes, 0),
    sourceFiles: source.length,
    sourceNonblankLoc: source.reduce((sum, record) => sum + record.lines, 0),
    sourceBytes: source.reduce((sum, record) => sum + record.bytes, 0),
    testFiles: tests.length,
    testNonblankLoc: tests.reduce((sum, record) => sum + record.lines, 0),
    documentationNonblankLoc: docs.reduce((sum, record) => sum + record.lines, 0),
    functionDefinitions: countMatches(source, functionPattern),
    controlFlowKeywords: countMatches(source, branchPattern),
    todoFixmeCount: countMatches(records, todoPattern),
    directPackageDependencies: 0,
    runtimeDependencies: ["Kujo >= " + ((fs.readFileSync(path.join(root, "kennel.toml"), "utf8").match(/minimum_version\s*=\s*"([^"]+)"/) ?? [null, "unknown"])[1])],
    largestSourceFiles: source.sort((a, b) => b.lines - a.lines).slice(0, 5).map(({ file, lines, bytes }) => ({ file, nonblankLoc: lines, bytes })),
  };
}

const baseline = inspect(path.resolve(baselineArg));
const current = inspect(path.resolve(currentArg));
const deltas = Object.fromEntries([
  "trackedFiles", "trackedBytes", "sourceFiles", "sourceNonblankLoc", "sourceBytes", "testFiles", "testNonblankLoc",
  "documentationNonblankLoc", "functionDefinitions", "controlFlowKeywords", "todoFixmeCount", "directPackageDependencies",
].map((key) => [key, current[key] - baseline[key]]));

fs.mkdirSync(path.dirname(path.resolve(outputArg)), { recursive: true });
fs.writeFileSync(outputArg, `${JSON.stringify({ schemaVersion: "muzzle.hardening-structure/v1", baseline, current, deltas }, null, 2)}\n`);
