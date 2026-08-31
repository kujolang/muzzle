#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const [rootArg, outputArg] = process.argv.slice(2);
if (!rootArg || !outputArg) {
  console.error("Usage: assemble-results.mjs <evaluation-root> <output.json>");
  process.exit(2);
}

const root = path.resolve(rootArg);
const readJson = (relative) => JSON.parse(fs.readFileSync(path.join(root, relative), "utf8"));
const readText = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const parseKeyValues = (content) => Object.fromEntries(content.trim().split("\n").map((line) => {
  const index = line.indexOf("=");
  return [line.slice(0, index), line.slice(index + 1)];
}));
const capability = (label) => ({
  runJson: JSON.parse(readText(`results/capabilities/${label}/run.json`)),
  artifactModes: parseKeyValues(readText(`results/capabilities/${label}/artifact-modes.txt`)),
  installerExit: Number(readText(`results/capabilities/${label}/install.exit`).trim()),
  installerExternalFileListBytes: Buffer.byteLength(readText(`results/capabilities/${label}/install-external-files.txt`)),
  workflowRaceExit: Number(readText(`results/capabilities/${label}/race.exit`).trim()),
  workflowRaceLog: readText(`results/capabilities/${label}/race.log`).trim(),
  policyRaceExit: Number(readText(`results/capabilities/${label}/policy.exit`).trim()),
});

const runtime = readJson("results/runtime-results.json");
const result = {
  schemaVersion: "muzzle.hardening-evaluation/v1",
  generatedAt: new Date().toISOString(),
  boundary: {
    baseline: {
      sha: "75c2e1d20ed060b22df01c44d28221cd672a02fa",
      timestamp: "2026-08-23T16:48:40-04:00",
      tag: null,
      selection: "Recorded starting SHA of the dedicated repository-hardening audit.",
    },
    current: {
      sha: "55c149271e3c6b81b993879d5bdd7f79e96a0cca",
      timestamp: "2026-08-30T19:28:33-04:00",
      tag: "v1.1.0",
    },
    alternativeBaseline: {
      sha: "f59db6dea559d3216dfe0ab41645c15ed5e16064",
      tag: "v1.0.0",
      reasonNotSelected: "Fourteen additional hardening/refactor commits precede the dedicated audit boundary; selecting v1.0.0 would mix two efforts.",
    },
  },
  environment: parseKeyValues(readText("results/environment.txt")),
  runtime,
  helperIsolationDiagnostic: readJson("results/helper-results.json"),
  structure: readJson("results/structure.json"),
  installFootprint: readJson("results/install-footprint.json"),
  eval: {
    definition: "eval-suite.json",
    baseline: { summary: readJson("results/eval/baseline/summary.json"), details: readJson("results/eval/baseline/last_run.json") },
    current: { summary: readJson("results/eval/current/summary.json"), details: readJson("results/eval/current/last_run.json") },
  },
  capabilities: { baseline: capability("baseline"), current: capability("current") },
  priorAuditSignal: {
    classification: "Observed; insufficient sample count for a statistical claim",
    startupAverageMs: { baseline: 426, current: 381, samples: 5 },
    fullLogBytes: { baseline: 4000000, current: 4000000 },
    jsonSummaryBytes: { baseline: 482, current: 531 },
    peakRssBytes: { baseline: 34648064, current: 34025472 },
    fiveConcurrentRunsMs: { baseline: 2614, current: 3245 },
  },
  tokenMeasurement: {
    status: "Not demonstrated",
    reason: "No provider tokenizer, model invocation, or provider usage receipt was available. Exact output bytes and lines are reported instead.",
  },
  verdict: {
    answer: "PARTIALLY",
    rationale: "Current independently passes all 11 matched outcome checks versus 2 for baseline, but it adds runtime, payload, code, and install-footprint costs and does not demonstrate token or build-speed gains.",
  },
};

const output = path.resolve(outputArg);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
