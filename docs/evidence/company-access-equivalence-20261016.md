# Company access equivalence — 2026-10-16

## Read-only production comparison

The requesting company administrator and the reported company member were
compared using selected account, membership, commercial project, workspace
grant, lease, reservation and credential metadata. No passwords, API secrets,
credential digests or production snapshots were exported into the repository.
The third company administrator was included in the authorization comparison.

All three have active company memberships with OrganizationAdministrator,
LegalSigner, LeaseRequester, BillingViewer and Developer roles, the same
OrganizationOwner commercial role, and the same company project. Their active
text and video capability leases have equivalent limits and expiry. Each has
an individual workspace authority. The external GLM route is tenant scoped;
company administrators have equivalent model lifecycle authority.

The reported member already has five active GLM-scoped credentials, all in the
correct company project; one has a nonzero inference-use counter. This proves
credential issuance and some inference admission occurred, not that every
client request completed. The exact original failed key request was not
captured. No credential was issued, retrieved or revoked for this comparison.

The company's two-node reservation still references its original sponsoring
administrator's lease and grant. There is no effective signed company contract
packet: current access is supplied by administrator-attested annual private
grants. The historical cancelled order is not effective authority.

## Corrections

- Key creation sends a supported relative lifetime; the controller uses its
  clock and preserves trial/order expiry caps and all scope checks.
- Expired or foreign trial records cannot shorten a company key lifetime or
  overwrite its company project. Refresh repairs blank or foreign trial
  project selection without changing an explicit company project.
- Specific key, project and entitlement refusals no longer collapse into the
  generic HTTP 409 resource-change message.
- Private-company administrators may select the same current company pool
  using their own capability lease and grant. The original sponsoring grant,
  lease and reservation term must also remain valid. Admission, reconciliation
  and credential issuance use the same predicate.
- Personal delivery ownership, workspace files and connection isolation are
  preserved. The public-cloud profile and other organizations receive no new
  authority. No production lease, membership or contract was fabricated.

## Verification

The pool fixture exercises three administrators, two reserved nodes, HTTP
reservation discovery and delivery submission with distinct personal leases,
directory/portal reopen, profile isolation, mismatched organization and grant,
missing sponsor, insufficient role, inactive membership and expiry. Existing
native contract, response privacy and reconciliation fixtures remain in the
full suite. No live delivery was created or model runtime restarted.

Live account login was not available for the reported member; verification uses
read-only production metadata and authenticated synthetic HTTP fixtures.

Validation passed: `moon fmt`, `moon info`, strict native check, 1,831/1,831
native workspace tests, 144/144 portal JavaScript tests, 28/28 documentation
tests, dependency/public-response isolation checks and browser bundle build.
The deployed customer JavaScript matches the tested bundle byte for byte.

Immutable releases (deployment uses resource-version and previous-image
guards, with private rollback snapshots):

- Controller: `sha256:f2affe85eca38e317e04a8a5e6ada1b4f3bbc411e8bd54f076339daee63e70c9`.
- Customer portal: `sha256:f4a7ba7d3ca63b53beb83ea8fd1e9653cab57d6478eb919e784eb5d056b99bf5`.
- Docs evidence refresh: `sha256:70d34ac545086d9319b35e2f78091bc6a7debcb3a966db8308b37355425bc6c1`.

The first documentation package drew from an outdated browser output folder.
The public asset comparison caught the mismatch. All three coursebook JSON
files were repackaged directly from the tested `docs-site` source; the
intermediate image is superseded by the digest above.
The live English coursebook, Chinese coursebook and evidence JSON now match
the corresponding tested source files byte for byte.
