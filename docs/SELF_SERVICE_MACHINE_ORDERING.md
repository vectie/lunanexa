# Self-service organization and machine ordering

This is the customer-facing path for a person who has no corporate system and
wants to buy machine-backed capacity before deploying or using a model.

## Customer journey

The enterprise portal deliberately presents six meaningful stages:

1. **Sign in or create an account.** The production identity gateway redirects
   to either the platform's public-sign-up-capable OIDC provider or an approved
   enterprise IdP. LunaNexa never receives the password. First sign-in creates
   an account and, when enabled, a bounded shared-MaaS trial.
2. **Create or join a customer.** Create an `Individual` or `Company` legal
   customer record, or accept an email-bound invitation. The creator receives
   organization-owner portal roles and a default project. If the account belongs
   to more than one customer, select one explicitly.
3. **Complete verification and terms.** Follow the external identity-verification
   action when required. A legal signer reviews the immutable machine terms and
   records clickwrap acceptance, or uses an already executed negotiated agreement.
4. **Choose service and capacity.** Select Shared MaaS, Dedicated MaaS, or Bare
   GPU. Machine offers show only commercial SKU, region, accelerator class/count,
   duration, price and live availability. Customers never choose a node or GPU ID.
5. **Review quote and pay.** LunaNexa derives organization, tenant, project and
   purchaser from the authenticated membership, signs a 15-minute quote, creates
   the order, and sends the browser to the external checkout. No capacity is
   allocated before a valid exact-amount payment callback.
6. **Provision and use.** A dedicated endpoint becomes a managed model deployment
   and exposes its canonical `/v1/workloads` path. Its one-time API key is durably
   bound to the paid order, model, project, expiry and selected deployment; an
   adapter that cannot enforce node-directed routing fails closed. A bare machine
   becomes an exclusive-node lease and appears in the existing secure SSH/WebIDE
   credential handoff. The order page can be safely reloaded and resumes provider
   actions and lifecycle state. Cancellation or failure displays compensation and
   refund progress.

The shared MaaS trial and API-key flow is separate from paid machine orders.
Ordering hardware does not bypass model approval, runtime readiness, access
revocation, sanitization, budget or release gates.

## Roles and privacy

- `OrganizationAdmin` and `LegalSigner` can see legal verification actions.
- `BillingViewer` can see legal/billing details but cannot operate verification.
- `Developer` sees only the organization summary and membership, never company
  registration numbers, tax identifiers, addresses or billing contacts.
- `LeaseRequester` may quote and order capacity.
- Every organization-scoped request uses `X-LunaNexa-Organization`; ambiguous
  membership fails closed.
- Customer API bodies reject tenant, organization, node, device and placement
  authority. Customer responses omit physical topology.

## Operator prerequisites

Before exposing the journey, an operator must:

1. deploy the PostgreSQL production profile and leader fencing;
2. deploy an approved OIDC gateway and either the LunaNexa-operated public
   identity profile in [`PLATFORM_IDENTITY.md`](PLATFORM_IDENTITY.md) or an
   approved enterprise federation;
3. configure identity-verification, payment and signature adapters, callback
   trust, action origins and durable outbox polling;
4. publish exactly one current `ReadyTemplate` whose `agreement_type` is
   `machine-self-service` and whose immutable `document_uri` is HTTPS or `/docs/`;
5. label eligible heartbeat inventory with trusted `lunanexa.io/region` values;
6. create active `BareMachine` and/or `DedicatedEndpoint` SKUs through
   `POST /v1/machine-commerce/operator/offerings`, using positive prices,
   supported duration bounds and approved dedicated model-template references;
7. keep the machine-commerce signing secret independent and at least 32 bytes;
8. pass the real-provider, object-storage, browser and physical-cluster release
   evidence gates.

An offering's `capacity_total` is only a commercial ceiling. Customer-visible
availability is the lower of that ceiling and fresh, healthy, SKU-compatible
heartbeat inventory after existing exclusive leases and dedicated reservations.
A missing or incorrect region label therefore fails closed.

`PaymentRefund` is an explicit provider request. Operators and adapters must not
reinterpret it as a new checkout. Capacity remains reserved until the signed
`Refunded` callback completes compensation, preventing unpaid reuse or a false
refund claim.

## APIs

Customer APIs:

- `GET/POST /v1/portal/self/organizations`
- `POST /v1/portal/self/invitations:accept`
- `GET /v1/portal/self/machine-offerings`
- `GET /v1/portal/self/machine-terms`
- `POST /v1/portal/self/machine-terms/accept`
- `POST /v1/portal/self/machine-quotes`
- `GET/POST /v1/portal/self/machine-orders`
- `GET /v1/portal/self/machine-orders/{id}/access`
- `POST /v1/portal/self/machine-orders/{id}/access-key`
- `POST /v1/portal/self/machine-orders/{id}/cancel`
- `POST /v1/portal/self/machine-orders/{id}/terminate`

Operator APIs:

- `GET /v1/machine-commerce/operator/snapshot`
- `POST /v1/machine-commerce/operator/offerings`
- `POST /v1/commercial/agreement-templates`
- the existing template-state transition route used to promote the reviewed
  machine agreement to `ReadyTemplate`.

All payment, refund and verification completion events enter through the signed
commercial provider callback. Repository tests prove state-machine behavior;
they do not replace real provider or hardware acceptance evidence.
