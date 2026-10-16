# GLM client compatibility and streaming — 2026-10-16

Acceptance endpoint: `https://suanli.kechuangfuwu.com:8443/user/v1`.
Public model alias: `glm-5.3.flash`.

## Reproduction and change

The customer's current API key successfully authenticated a bounded chat
request. Independently, the live adapter rejected explicit `null` values for
optional fields such as `max_tokens`, `tools`, and `temperature`, returning the
same generic HTTP 400 reported by the customer in Trae. The customer's exact
Trae request body was not collected, so this proves the compatibility defect
without claiming that its complete request was reproduced.

After rollout, the customer's Trae retry returned the new output-budget error:
`max_tokens must be between 1 and 131072`. This confirms that the remaining
Trae request specifies an invalid output budget; its exact numeric value was
not collected. TRAE documents separate input and output settings under the
custom model's Advanced configuration → Context window. The customer was
instructed to set output to 16384 and retry, independently of the model's
850000-token total context window. Reference:
<https://docs.trae.cn/ide_models>.

The next Trae retry reached `RequestBudgetExceeded`. The mounted live
administrator policy still capped canonical input at 65536 bytes, although its
HTTP body ceiling, the checked-in deployment profile and backend defaults allow
1048576 bytes. Only that input-policy value was aligned to the existing body
ceiling; the controller was restarted and its rollout completed. Input here is
serialized UTF-8 payload bytes, not the model's context-token count. A synthetic
72398-byte canonical tool request then returned HTTP 200 with a valid
`lookup_status` call. The prior policy and deployment are retained privately in
the same release directory.

The customer then reached the runtime stream and reported `RuntimeUnavailable`.
Both multipart Chat text (`content: [{type: "text", text: ...}]`) and a
synthetic Chat tool-result transcript reproduced that stream failure. The
runtime adapter had forwarded Chat message shapes directly as Responses input.
The follow-up conversion maps text parts to `input_text`, assistant tool calls
to `function_call` items and tool results to `function_call_output` items,
preserving call IDs, arguments and order. Explicit canonical `input` remains
unchanged. Unsupported content fails closed rather than being silently dropped.
Reference: <https://developers.openai.com/api/docs/guides/migrate-to-responses>.

The input-policy rollout was completed as settings generation 4 across the
controller, four node agents and the lease agent. All six existing consumers
completed their rollouts.

The adapter now treats null optional chat parameters as omitted. Required
fields, JSON types, message count and output budgets remain validated. Both
normal and streaming validation return bounded, content-free explanations of
invalid fields and token limits. No raw prompts or API secrets are logged.

## Live verification

- Normal request with nullable optional fields: HTTP 200, `NULL_FIELDS_OK`,
  `finish_reason=stop`.
- Streaming request with nullable optional fields: HTTP 200, `NULL_STREAM_OK`,
  stop event, receipt and `[DONE]`.
- Required synthetic function call: HTTP 200, `lookup_status`, valid JSON
  arguments and `finish_reason=tool_calls`. No tool was executed.
- Large synthetic tool request: 72398 canonical input bytes, HTTP 200, 9175
  runtime-reported input tokens, valid function call and receipt.
- `max_tokens: -1`: HTTP 400 identifying the valid range of 1–131072 and the
  supported omission/null default; no request content was reflected.
- Multipart Chat text stream after conversion: HTTP 200, `MULTIPART_OK`, stop
  event, receipt and `[DONE]`; no error event.
- Chat tool-result history stream after conversion: HTTP 200, `TOOL_HISTORY_OK`,
  stop event, receipt and `[DONE]`; no error event.
- Complete synthetic streamed tool round trip: received `lookup_status` with
  valid JSON arguments and `finish_reason=tool_calls`, submitted a simulated
  result using the returned call ID, then received `TOOL_ROUND_TRIP_OK`, stop,
  receipt and `[DONE]`. No external tool was executed.

Controller image:
`moon/lunanexa-control@sha256:d1199b093b59e611cb59702f0aa716c86755f6623c9c989489c19abc3791208e`.
The controller rollout completed. Its previous deployment specification and
release artifacts remain in the private management-host release directory
`lunanexa-openai-null-20261016`.

The follow-up Chat-to-Responses conversion was released as:
`moon/lunanexa-control@sha256:3a500b08bff3af3904f2871720f5f9651a680bac49b7c7021f98aa03779a3488`.
Its controller rollout completed before the multipart and tool-history checks.

Targeted nullable-field native regressions, all 47 runtime package tests, strict
native checking and both Linux release builds passed. The consolidated gate
passed `moon info`, `moon fmt`, `moon check --target native --deny-warn` and
`moon run scripts/test-native.mbtx` (1828 passed, 0 failed). The test run used an
unlimited stack and a private Clang wrapper selecting `-O0` for native test
compilation.
After the conversion release, the customer retried TRAE and confirmed:
“It works now”.

`sh scripts/check-release.sh` passed dependency, image, contract, secret and
response scans, including 30 isolation/response scan fixtures and 14 secret
scanner fixtures. `sh scripts/process-recovery-test.sh` passed process restart,
persisted node/controller state and stale-controller-epoch rejection.

The process recovery harness was aligned with the workspace's qualified native
binary paths and the required Cosign trusted-root environment reference. Its
scenario exercises process restarts and persisted state, without model artifact
materialization or signature-verification acceptance claims.
