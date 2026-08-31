#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const [rawInput, output] = process.argv.slice(2);
if (!rawInput || !output) {
  console.error("Usage: analyze.mjs <raw-results.json> <evaluation-results.json>");
  process.exit(2);
}

const raw = JSON.parse(fs.readFileSync(rawInput, "utf8"));
const records = raw.records.filter((record) => record.phase === "measured");

function percentile(sorted, probability) {
  return sorted[Math.max(0, Math.ceil(probability * sorted.length) - 1)];
}

function stats(values) {
  const data = values.filter((value) => Number.isFinite(value)).sort((a, b) => a - b);
  const mean = data.reduce((sum, value) => sum + value, 0) / data.length;
  const variance = data.length > 1
    ? data.reduce((sum, value) => sum + ((value - mean) ** 2), 0) / (data.length - 1)
    : 0;
  return {
    n: data.length,
    min: data[0],
    max: data.at(-1),
    mean,
    median: data.length % 2 === 1 ? data[(data.length - 1) / 2] : (data[data.length / 2 - 1] + data[data.length / 2]) / 2,
    p95: percentile(data, 0.95),
    p99: percentile(data, 0.99),
    standardDeviation: Math.sqrt(variance),
  };
}

const workloadNames = [...new Set(records.map((record) => record.workload))];
const metrics = ["wallMs", "userMs", "sysMs", "peakRssBytes", "stdoutBytes", "stdoutLines", "logBytes", "reportedDurationMs"];
const workloads = {};
for (const name of workloadNames) {
  workloads[name] = {};
  for (const label of ["baseline", "current"]) {
    const samples = records.filter((record) => record.workload === name && record.label === label);
    workloads[name][label] = {
      sampleCount: samples.length,
      successCount: samples.filter((sample) => sample.success && !sample.parseError).length,
      metrics: Object.fromEntries(metrics.map((metric) => [metric, stats(samples.map((sample) => sample[metric]))]).filter(([, value]) => value.n > 0)),
      artifactModes: [...new Set(samples.map((sample) => sample.logMode).filter(Boolean))],
      schemaVersions: [...new Set(samples.map((sample) => sample.schemaVersion).filter(Boolean))],
      displayTruncatedValues: [...new Set(samples.map((sample) => sample.displayTruncated).filter((value) => value !== undefined))],
    };
  }
  const baseline = workloads[name].baseline.metrics;
  const current = workloads[name].current.metrics;
  workloads[name].change = {};
  for (const metric of metrics) {
    if (!baseline[metric] || !current[metric]) continue;
    const absolute = current[metric].median - baseline[metric].median;
    const pairedDifferences = [];
    const sampleNumbers = [...new Set(records.filter((record) => record.workload === name).map((record) => record.sample))];
    for (const sample of sampleNumbers) {
      const baselineSample = records.find((record) => record.workload === name && record.sample === sample && record.label === "baseline");
      const currentSample = records.find((record) => record.workload === name && record.sample === sample && record.label === "current");
      if (Number.isFinite(baselineSample?.[metric]) && Number.isFinite(currentSample?.[metric])) pairedDifferences.push(currentSample[metric] - baselineSample[metric]);
    }
    workloads[name].change[metric] = {
      medianAbsolute: absolute,
      medianPercent: baseline[metric].median === 0 ? null : (absolute / baseline[metric].median) * 100,
      pairedDifference: pairedDifferences.length > 0 ? stats(pairedDifferences) : null,
      pairedCurrentSlowerCount: pairedDifferences.filter((difference) => difference > 0).length,
    };
  }
}

const result = {
  schemaVersion: "muzzle.hardening-evaluation/v1",
  generatedAt: new Date().toISOString(),
  boundary: {
    baselineSha: "75c2e1d20ed060b22df01c44d28221cd672a02fa",
    currentSha: "55c149271e3c6b81b993879d5bdd7f79e96a0cca",
  },
  benchmarkConfiguration: raw.configuration,
  workloads,
  limitations: [
    "No provider tokenizer was installed; exact LLM billing-token counts are not claimed.",
    "Latency and resource results are host-specific and should be reproduced on release CI hardware.",
    "p99 equals the maximum for n=10 or n=15 and is reported only as an observed tail, not a stable population estimate.",
  ],
};

fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
