# Workspace authorization concurrency

The isolated browser acceptance exposed transient static-module loading failures.
The gateway resolves a stable Kubernetes Service, not a persisted Pod IP. Each
HTTP/static request independently called the controller for authorization with a
5-second timeout. A 32-request same-session static asset burst reproduced 16
HTTP 503 responses at approximately 5.1 seconds; a 12-request burst passed but
its tail reached 3.12 seconds. This is a reproduced authorization fan-out failure,
not proof that every historical browser error has the same cause.

The bridge now shares an **in-flight** check for an identical opaque session
token. No completed decision is cached; later requests perform a fresh check.
Different sessions never share results. Failure/cancellation wakes waiters with
unavailable authority, and session removal/expiry is checked again after waiting.
This does not extend grant lifetimes or relax access, route or tenant policy.

macOS and Linux native bridge tests passed 10/10, covering concurrent coalescing,
no cached decision after revocation, failure fan-out, independent sessions and
leader cancellation with subsequent recovery.

Isolated gateway image:
`sha256:662de79bd9ab38d1b169d572a6fd0bd7a72014608dfbc9c69e376bcf4cd5e153`.
Only the gateway executable was overlaid on the previous acceptance image;
workspace and model-proxy binaries were preserved. Kubernetes rollout completed.
The same 32-request campaign then passed 32/32, all HTTP 200, approximately
0.41–0.53 seconds. Persistent output listing and download hash also passed.

Live revocation recheck: HTTP 200 / WebSocket 101 before revocation; the existing
socket closed with policy code 1008 after 5597 ms; subsequent HTTP/socket calls
returned 401, cross-site socket 403, and a forged cookie 401. This validates
the existing periodic revocation bound, not instantaneous revocation.

Real browser follow-up on this image completed the handoff, removed the loading
overlay, restored the named test workflow and displayed both retained videos
after clicking Assets. Remaining cross-tenant/upload/partition campaigns require
separate evidence. No actual model inference or Spark hardware compatibility is
asserted here.
