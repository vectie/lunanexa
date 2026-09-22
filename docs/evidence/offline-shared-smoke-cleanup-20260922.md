# Shared browser smoke identity cleanup

After both the enterprise-browser checks and the technical-waiver dispatcher
checks completed, the original MoonTown shared smoke identity was retired.
The existing exact-target cleanup script revoked both its initial test account
and its actual OIDC account, and deleted the exact temporary IdP user.

A request to `/v1/auth/self` with the old cookie and bearer session returned
HTTP **401**, `Unauthenticated`. The identity edge's `/auth/session` endpoint
still returned HTTP 200 for the cached cookie; this was not counted as account
authorization. The authenticated controller request is the revocation check.

The following five temporary files were deleted from the management host's
`.config/moontown` directory: `offline-acceptance-cookies`, `smoke-cookies`,
`identity-smoke-cookies`, `smoke-active-account`, and `smoke-login.json`.
They are not retained as recoverable credentials. `service.env`, production
credentials, rollback material and audit records were not removed.

The separate technical-waiver test identity's cleanup is recorded in
`offline-technical-waiver-production-20260922.json`.

After all images were published, the exact temporary
`lunanexa-runtime-qualification/offline-production-builder` Pod was deleted,
removing its live host/containerd access. Other namespace resources were left
untouched. Source stages, published images and private rollback archives remain;
the builder can be recreated from the deployment tooling if needed.
