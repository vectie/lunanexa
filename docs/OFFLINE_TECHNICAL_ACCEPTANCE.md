# Single-order technical acceptance

This administrative verification is disabled by default. It is not a customer
payment flow and does not replace normal commercial policy or documentary KYC.

`LUNANEXA_TECHNICAL_ACCEPTANCE_AUTHORIZATION_JSON` enables one exact order,
purchaser subject, authorization-reference document and expiry. Its keys are
`order_id`, `purchaser_subject_ref`, `user_authorization_ref`, and
`expires_unix_ms` (decimal string). Remove the configuration after verification.
An expired configuration does not prevent controller startup or reversal.

A genuine active PlatformOperator browser session may POST
`/v1/offline-commerce/operator/technical-acceptance-waivers` with `order_id`,
`expected_generation`, `waiver_id`, `authority_target_ref`, `grant_id`,
`expires_unix_ms`, `user_authorization_ref`, and `reason`. Static operator tokens
are insufficient. The server constructs the immutable waiver and records the
operator account, subject and non-secret session ID; no bearer token is stored.

The order must have a zero-valued immutable quote, the exact service
`technical-workspace-acceptance`, a `technical-acceptance-` organization and
tenant, no agreement or artifacts, and an independent Requested Developer
workspace lease. The purchaser must have a dedicated `technical-` email, an
active HTTPS identity account with a current real login session, and an exact
administrator-issued Developer grant. Order/lease/waiver expire in at most one
hour. The scope cannot extend the waiver or authorize another order. GPU jobs,
exclusive machines, quota purchases, model deployment, and inference requests
are not part of this procedure.

The record explicitly labels contract, payment, invoice and internal review
requirements **waived**, never evidence accepted, paid, invoiced, or signed.
Identity uses a separately recorded actual OIDC verification method, explicitly
not commercial KYC. The original fulfillment policy is unchanged. The audit
action is `offline.technical-waiver.authorize`.

Normal dispatcher activation and reversal then operate on the exact lease.
Activation rechecks scope, identity, grant, binding and expiry. If any technical
authorization becomes invalid while work is pending, the executor first revokes
the exact bound lease (including crash-created active access), then persists a
rejected authority result; the order can be cancelled/expired. Reversal remains
available after the scope, identity or grant expires. A reserved technical target
cannot be reused by another commercial order; snapshot restoration checks these
bindings as well.

The one-off `scripts/qualify-offline-technical-waiver.mbtx` driver records actual
OIDC `false → true → false` access and actual dispatcher activation/reversal.
It never manufactures payment/signature/invoice artifacts or calls inference.
Run its phases only for the explicitly named dedicated test identity. Retain
the order and audit records; revoke its grant, workspace user and platform
account, delete the exact temporary IdP identity and credentials, and confirm
the old browser session returns HTTP 401 when finished. The current membership
API is create-only: retain that inert membership as an audit record rather
than rewriting a PostgreSQL snapshot. Its `active` field is not evidence of
effective access after the subject account and workspace authorities are revoked.
