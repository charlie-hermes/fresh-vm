import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const version = process.env.PAPERCLIP_VERSION;
assert(version, "PAPERCLIP_VERSION is required");
const root = `/opt/paperclip/${version}/node_modules`;
const adapter = await import(pathToFileURL(
  `${root}/@paperclipai/hermes-paperclip-adapter/dist/server/execute.js`,
));
const fingerprints = await import(pathToFileURL(
  `${root}/@paperclipai/server/dist/services/effective-run-config-fingerprints.js`,
));

const prompt = adapter.buildPrompt(
  {
    agent: { id: "agent", companyId: "company", name: "Regression" },
    runId: "run",
    context: {},
    config: {},
  },
  {
    promptTemplate: "api={{paperclipApiUrl}}",
    paperclipApiUrl: "http://paperclip-host:3100",
  },
);
assert.match(prompt, /api=http:\/\/paperclip-host:3100\/api/);

const make = (runId, updatedAt, model = "gpt-5.6-sol") =>
  fingerprints.createEffectiveRunConfigFingerprints({
    session: { runId, issueConfigRevisionAt: updatedAt, model },
    workspace: { cwd: "/one", executionRunId: runId },
    lease: { leaseId: runId },
  });
const stableA = make("run-a", "2026-01-01T00:00:00Z");
const stableB = make("run-b", "2026-02-01T00:00:00Z");
assert.equal(
  fingerprints.diffEffectiveRunConfigFingerprints(stableA, stableB).hasChanges,
  false,
);
assert.deepEqual(
  fingerprints.diffEffectiveRunConfigFingerprints(
    stableA,
    make("run-c", "2026-03-01T00:00:00Z", "different-model"),
  ).changedCategories,
  ["session"],
);

console.log("Paperclip adapter and session-fingerprint regressions passed");
