# Staged release artifacts — aad1703

Build-only record, 2026-09-23. No rollout, grant renewal or workload stop is
performed by this packaging workflow. A published image is not UI acceptance.

## Source provenance

- LunaNexa: clean `git archive` of `aad1703b585a007f8744e1b593f7146beaa9d967`.
- MoonLeaf: clean `git archive` of `066efc2f4d8f4acdb2e13aec2a7cd9103fb028db`.
- Archive SHA-256, respectively:
  `eb35982fe8db57532447cf55ab5e321aa2a6e0d8a3c98cc4ea2cad93256afd35`,
  `07d1711cf592aad7903add838e8261dbd3a7f076dc31d6a87adf87dc4b4d1782`.
- Management source: `/home/HwHiAiUser/release-aad1703/lunanexa` with sibling
  `moonleaf`. Existing dependency caches were reused, not uncommitted sources.
- ARM64 source: `/home/wlc001s/release-aad1703/lunanexa` on Spark .176, with the
  same source archives. Existing extracted `libpq-root` headers/libraries were
  selected explicitly; no host package installation or GPU execution occurred.

## Registry-verified images

Registry prefix: `lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/`.
Each listed digest was checked through TLS-verified registry HEAD, HTTP 200,
matching `docker-content-digest` after import and push.

| Component | Repository | Manifest digest |
| --- | --- | --- |
| Browser sites, amd64 | `moon/lunanexa-web` | `sha256:6b38c7ce3394b9d06c36bbc41d0f0bf3cb5e42db72eebe84101d9655951bd62f` |
| WebIDE gateway, amd64 | `acceptance/webide-runtime` | `sha256:6a4db6d362d656a97bccc154a9f3045afad526997392df5513a066db6590d3fc` |
| Node agent, arm64 | `lunanexa/node` | `sha256:8a40c6364ac1fd964c4e55c136be3cfc1fb6da87daa0c2b26029472e055fc325` |
| Controller, amd64 | `moon/lunanexa-control` | `sha256:5b80b2dc4b73f9e9936a2d553ed6fb0496109fce9448b174a0cc0319997ffd3a` |

Controller release compilation completed successfully (156 build tasks).
Controller binary SHA-256:
`8da46fb2ec3909542656a1e4f757689306791f393e8dc461a7eedff5fab7ea0d`.
The compiler emitted the existing async C declaration warning for
`posix_spawn_file_actions_addchdir_np`; linking completed. Browser installer-ui
also emitted an existing unused-import warning. Neither is suppressed here.

## Browser and gateway build evidence

The existing `build-browser-bundles.sh` completed, including its source/bundle/
HTML hashes and OFL font digest gate. Public origin rendering uses Operator
`http://106.39.18.146:4174` and Enterprise `http://106.39.18.146:5002`. The
operator-open setting was rendered by the existing script. No credentials were
added to browser assets. Private fonts were not included.

Browser dist: `/home/HwHiAiUser/release-aad1703/browser-dist`.
Gateway amd64 binary SHA-256:
`abed8cb70a562f2acb766df2f8eb5c32baaf4091220e021c6bf95af58b091a7c`.

The ARM64 gateway was also compiled from the same source, but not packaged:
the current gateway deployment runs on amd64 management, so no additional image
is needed for this rollout. Both architectures' source builds remain available.
Node ARM64 binary SHA-256:
`bbccde6456908d1027bf6de4810a040b260dfae0405489e80f0f6b95870cf682`.
Gateway ARM64 binary SHA-256:
`9c1e158228743231f482783f0ce4dd98381a68433aa61da90522980da65a3606`.
The node binary's `ldd` closure is the ARM64 libc and loader; libpq build headers
were required by shared C stubs but no PostgreSQL runtime library is linked into
the resulting node binary.

OCI archives are retained under
`/home/HwHiAiUser/offline-production-build.TT3wLN/` as
`web-aad1703.oci.tar`, `webide-aad1703.oci.tar`, and
`node-aad1703-arm64.oci.tar`, plus `control-aad1703.oci.tar`. Existing image archives and live deployments were
not overwritten. Main-task rollout must capture current Deployment specs and
validate the entire public flow separately.
