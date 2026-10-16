# GLM request deadline — 2026-10-16

The reported TRAE request failed after running for several minutes. The
controller recorded `RuntimeInvocationFailed` with `deadline_exceeded` at
119,969 ms. The live administrator policy set both the default OpenAI request
deadline and maximum runtime deadline to 120,000 ms. This is a global duration
policy, independent of the account's model scopes and key request counter.

At the user's request, both live deadline values were increased to 1,800,000 ms
(30 minutes), and the policy generation advanced from 4 to 5. The ConfigMap
update tested both resource version and the complete previous settings value.
A private rollback copy was retained on the management host. The controller,
four existing node agents and one lease agent rolled out successfully with the
new generation. The GLM runtime was not restarted.

The live policy was read back after rollout and confirmed both new values.
The running controller's authenticated `/v1/settings/effective` response also
confirmed generation 5 and both 1,800,000 ms deadlines. The check used the
existing deployment credential reference in memory without logging its value.
The identity edge's ordinary inference proxy has buffering disabled and a
3,600-second read timeout; its separate 180-second offline-transfer location
does not handle model inference. A synthetic direct GLM Responses request
completed with nonempty assistant text after rollout. This does not establish
that TRAE itself permits a 30-minute connection; a client-side timeout can
still be shorter than the service deadline.

Both shipped deployment policy documents now carry the 30-minute deadline.
The native deployment settings fixture validates both documents against the
typed settings contract and checks their deadline values agree. The in-code
fallback retains its conservative two-minute limit for installations without
an explicit administrator policy document; this deployment mounts that
document and uses its 30-minute values.

No password, API secret, prompt or production state snapshot is included here.

Validation passed: `moon fmt`, `moon info`, strict native check, all 1,831
native workspace tests, 144 portal JavaScript tests, 28 documentation tests,
dependency/public-response isolation checks and browser bundle verification.
