# TRAE stream investigation — 2026-10-16

## Confirmed scope

Mac TRAE's Add Model connectivity check returned `RuntimeUnavailable` at
13:43 Beijing time. Its retained settings use the supported
`https://suanli.kechuangfuwu.com:8443/user/v1` URL and `glm-5.3.flash`.
No model was saved or activated by the investigator.

The same existing key completed ordinary Chat Completions streams, including
a synthetic tool transcript and a request through the Mac's configured HTTP
proxy. Direct GLM Responses requests completed for automatic, required, named,
and disabled tool choice. These probes do not prove TRAE's connectivity check
passes.

## Safe diagnostics

Both streaming and ordinary workload failures now emit the operator event
`RuntimeInvocationFailed`. Outcomes use a closed set of adapter categories or
a bounded HTTP status. Exception strings, upstream bodies, prompts, keys,
endpoints, and generated output are excluded. Workload identifiers are hashed
for correlation. Failure to record diagnostics cannot replace the original
inference error.

The deployed controller is
`sha256:d1f08aa0bfb601b8b00cf3f4f291267209878994e397085fe7615918fb25a504`.
Deployment used resource-version and previous-image guards; the prior immutable
controller remains available for rollback.

A deliberately invalid synthetic transcript produced the expected
`invalid_tool_call_role` operator event. A subsequent ordinary stream through
the Mac proxy returned HTTP 200, a stop finish reason, and `[DONE]`.
The privacy regression test and strict native check passed before deployment.
Temporary authorization-header files were removed after probing.

## Resolution

The fresh user-operated TRAE retry recorded `unsupported_capability` in 5–6 ms,
before the adapter contacted GLM. TRAE's Model ID row had its green Multimodal
switch enabled. The user disabled it and confirmed Add Model succeeded.
The endpoint supports text and tools; enabling a multimodal connection check
is incompatible with that contract. No key replacement or runtime restart was
needed.

The bilingual MaaS instructions and public docs now identify the exact
Multimodal switch beside Model ID. Published assets were compared byte for
byte with the tested build. New immutable images:

- Customer portal: `sha256:8e24599389337b13643b7c4e120878d70e08543e2e75c379827317d2ecb355a4`.
- Docs: `sha256:eb64b375e9c55ebb4230f2b5b3968526a24eb57070eef83c8a18929cd57f3423`.

Validation: 1,830/1,830 complete native workspace tests; strict native check;
87/87 enterprise JavaScript tests; 28/28 docs tests; browser bundle verification;
live public asset digests and rendered Chinese guide. Temporary authorization
headers and the uncropped private TRAE screenshot were removed.
