import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  hasWorkspaceOverride,
  normalizeSuccessfulText,
  secureUrl,
  tokenBindingForUrl,
} from "./client-core.mjs";

test("security-sensitive settings are machine scoped", async () => {
  const manifest = JSON.parse(
    await readFile(new URL("./package.json", import.meta.url), "utf8"),
  );
  const properties = manifest.contributes.configuration.properties;
  assert.equal(properties["lunanexa.apiBaseUrl"].scope, "machine");
  assert.equal(properties["lunanexa.subjectRef"].scope, "machine");
});

test("runtime override detection rejects both workspace layers", () => {
  assert.equal(hasWorkspaceOverride(undefined), false);
  assert.equal(hasWorkspaceOverride({ globalValue: "subject-global" }), false);
  assert.equal(hasWorkspaceOverride({ workspaceValue: "subject-repo" }), true);
  assert.equal(
    hasWorkspaceOverride({ workspaceFolderValue: "subject-folder" }),
    true,
  );
  assert.equal(
    hasWorkspaceOverride({ workspaceLanguageValue: "subject-language" }),
    true,
  );
  assert.equal(
    hasWorkspaceOverride({
      workspaceFolderLanguageValue: "subject-folder-language",
    }),
    true,
  );
  assert.equal(hasWorkspaceOverride({ workspaceValue: "" }), true);
});

test("token keys bind to a canonical HTTPS origin, not a path", () => {
  const first = tokenBindingForUrl("https://EXAMPLE.com:443/control/");
  const second = tokenBindingForUrl("https://example.com/another/base");

  assert.equal(first.origin, "https://example.com");
  assert.equal(first.secretKey, second.secretKey);
  assert.match(
    first.secretKey,
    /^lunanexa\.inferenceBearerToken\.v2\.[a-f0-9]{64}$/,
  );
});

test("scheme, host, and non-default port changes use different token keys", () => {
  const production = tokenBindingForUrl("https://cluster.example");
  const otherHost = tokenBindingForUrl("https://other.example");
  const otherPort = tokenBindingForUrl("https://cluster.example:8443");
  const loopback = tokenBindingForUrl("http://127.0.0.1:8080");

  assert.notEqual(production.secretKey, otherHost.secretKey);
  assert.notEqual(production.secretKey, otherPort.secretKey);
  assert.notEqual(production.secretKey, loopback.secretKey);
});

test("credential URLs and insecure non-loopback origins are rejected", () => {
  assert.throws(
    () => secureUrl("https://token@example.com", "API base URL"),
    /must not contain credentials/,
  );
  assert.throws(
    () => secureUrl("https://example.com/?next=evil", "API base URL"),
    /query parameters/,
  );
  assert.throws(
    () => secureUrl("http://example.com", "API base URL"),
    /must use HTTPS/,
  );
  assert.equal(
    secureUrl("http://[::1]:8080/base", "API base URL").origin,
    "http://[::1]:8080",
  );
});

test("normalization prefers explicit canonical text shapes", () => {
  assert.deepEqual(
    normalizeSuccessfulText(
      { output: { text: "normalized", output_text: "upstream" } },
      100,
    ),
    { text: "normalized", truncated: false },
  );
  assert.deepEqual(
    normalizeSuccessfulText({ output: { output_text: "upstream" } }, 100),
    { text: "upstream", truncated: false },
  );
});

test("generic output is bounded without displaying response metadata", () => {
  const normalized = normalizeSuccessfulText(
    {
      output: { kind: "fake.text.chunk", value: 7 },
      audit_receipt: "receipt-must-not-be-in-output",
      internal_note: "also-not-output",
    },
    1_000,
  );

  assert.equal(
    normalized.text,
    '{\n  "kind": "fake.text.chunk",\n  "value": 7\n}',
  );
  assert.equal(normalized.truncated, false);
  assert.doesNotMatch(normalized.text, /receipt-must-not-be-in-output/);
  assert.doesNotMatch(normalized.text, /also-not-output/);
});

test("normalized output reports local truncation", () => {
  assert.deepEqual(
    normalizeSuccessfulText({ output: { output_text: "abcdefgh" } }, 5),
    { text: "abcde", truncated: true },
  );
});
