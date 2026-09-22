# Explicit offline technical-acceptance waiver

## Authorization source

On 2026-09-22, in the deployment task conversation, the platform owner stated:

> 给你这个线下的测试豁免 “真实合同、付款、发票和审核”

This records that instruction. It is not a signature by a customer, a bank
receipt, an issued invoice, a finance approval, or a legal opinion.

## Implementation scope

The authorization is used only for an independent, zero-price technical
acceptance order and its exact short-lived workspace lease. A genuine operator
session records the waiver, actor, reason, expiration and target. Its four
exemptions remain labelled **Waived**, never evidence of payment or execution.
Ordinary commercial policy and orders retain all existing requirements.

The test does not waive genuine account authentication, tenant/subject binding,
an administrator-issued workspace grant, target isolation, expiry enforcement,
callback authentication or durable audit. OIDC identity verification is
identified as such, not as commercial KYC certification. The allowed target is
a WorkspaceLease; this authorization does not provision a bare machine,
change a model deployment or start inference. The waiver cannot be converted
to a paid commercial order or moved to a different target.

The deployment switch is disabled by default and binds only
`technical-acceptance-waiver-order-20260922`, purchaser
`subject-a8a646206b6dd368534b3277`, this authorization reference, and a finite
expiry. Removing that switch or allowing it to expire cannot block reversal.
The switch is to be removed again after the isolated live test.

The acceptance checks must observe the real dispatcher perform activation and
reversal. Exemption expiry prevents a new activation but must never prevent
cleanup or revocation. Test identities and access are revoked after completion.

## Status

Authorized, implemented and live-tested. The final native suite passed 1140/1140, including
default-denial, exact-scope, identity, immutable-binding, restoration and
invalid-authorization compensation checks. Independent code review found no
remaining blocking issue. Live dispatcher activation and reversal both completed;
the actual OIDC subject observed `false → true → false` workspace authorization.
See `offline-technical-waiver-production-20260922.json` for the authority receipts.
The temporary deployment switch has been removed again. Dedicated test identity,
account, workspace user and grant were revoked; old authenticated access returned
HTTP 401. The create-only membership record remains inert for audit, not an
effective authorization. None of this attests real signing, payment or invoicing.
