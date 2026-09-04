///|
fn enterprise_portal_path(path : String) -> Bool {
  path == "/v1/portal" || path.has_prefix("/v1/portal/")
}

///|
fn decode_portal_membership(body : String) -> @portal.EnterpriseMembership? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_portal_agreement(body : String) -> @portal.PortalAgreement? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_signature_request(body : String) -> @portal.SignatureRequest? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
fn decode_lease_submission(body : String) -> @portal.LeaseRequestSubmission? {
  try {
    let value = @json.parse(body)
    if json_has_forbidden_lease_field(value) {
      None
    } else {
      Some(@json.from_json(value))
    }
  } catch {
    _ => None
  }
}

///|
fn json_has_forbidden_lease_field(value : Json) -> Bool {
  match value {
    Object(fields) => {
      for key, child in fields {
        let normalized = key.to_lower()
        if normalized == "password" ||
          normalized == "private_key" ||
          normalized == "privatekey" ||
          normalized == "secret" ||
          normalized == "credential" ||
          normalized == "access_credential_ref" ||
          normalized == "node_id" ||
          json_has_forbidden_lease_field(child) {
          return true
        }
      }
      false
    }
    Array(values) => values.any(json_has_forbidden_lease_field)
    _ => false
  }
}

///|
fn decode_lease_review(body : String) -> @portal.LeaseReview? {
  Some(@json.from_json(@json.parse(body))) catch {
    _ => None
  }
}

///|
priv struct PortalApiKeyIntent {
  key_id : String
  project_id : String
  display_name : String
  scopes : Array[@access.ApiKeyScope]
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
} derive(FromJson)

///|
fn decode_portal_api_key(body : String) -> PortalApiKeyIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn portal_error_reply(error : Error) -> HttpReply {
  match error {
    @portal.PortalError::Unauthorized(_) =>
      api_error(
        403, "PortalAccessDenied", "enterprise role is insufficient", false,
      )
    @portal.PortalError::TenantMismatch =>
      api_error(
        403, "TenantMismatch", "request crosses the tenant boundary", false,
      )
    @portal.PortalError::AgreementRequired =>
      api_error(
        409, "AgreementRequired", "an executed agreement is required before requesting a lease",
        false,
      )
    @portal.PortalError::StaleGeneration =>
      api_error(
        409, "StaleGeneration", "portal state changed; refresh before retrying",
        true,
      )
    @portal.PortalError::IdempotencyConflict(_) =>
      api_error(
        409, "IdempotencyConflict", "idempotency key identifies a different request",
        false,
      )
    @portal.PortalError::AlreadyExists(_) =>
      api_error(409, "AlreadyExists", "portal record already exists", false)
    @portal.PortalError::NotFound(_) =>
      api_error(404, "NotFound", "portal record was not found", false)
    _ => api_error(400, "PortalRejected", "portal request was rejected", false)
  }
}

///|
async fn ApiService::portal_subject(
  self : ApiService,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> String? {
  match self.enterprise_session_subject(headers) {
    Some(subject_ref) => return Some(subject_ref)
    None => ()
  }
  if !bearer_authorized(headers, self.inference_token) {
    return None
  }
  trusted_workspace_subject(headers, allow_asserted_subject)
}

///|
async fn ApiService::approve_portal_lease(
  self : ApiService,
  portal : @portal_store.FilePortalStore,
  review : @portal.LeaseReview,
  now_unix_ms : Int64,
) -> HttpReply {
  guard review.node_id is Some(node_id) else {
    return api_error(
      400, "InvalidRequest", "approval requires an assigned node", false,
    )
  }
  guard self.exclusive_lease_store is Some(exclusive_leases) else {
    return api_error(
      503, "ExclusiveLeaseUnavailable", "durable exclusive-node lease authority is unavailable",
      true,
    )
  }
  guard portal.lease_request(review.request_id) is Some(request) else {
    return api_error(404, "NotFound", "lease request was not found", false)
  }
  if request.state == Approved &&
    request.assigned_node_id == Some(node_id) &&
    request.decision_receipt == Some(review.evidence_receipt) {
    return json_reply(200, request.to_json())
  }
  if request.state != Submitted ||
    request.generation != review.expected_generation {
    return api_error(
      409, "StaleGeneration", "lease request changed; refresh before retrying", true,
    )
  }
  if !self.node_exists(node_id) {
    return api_error(
      409, "NodeUnavailable", "assigned node is not enrolled", false,
    )
  }
  if self.management_database is Some(_) {
    let duration_milliseconds = request.submission.expires_unix_ms -
      request.submission.starts_unix_ms
    let expected_seconds = (duration_milliseconds + 999L) / 1000L
    let expected_cost = try
      @commercial.estimate_cost(
        expected_seconds,
        self.exclusive_lease_unit_price,
      )
    catch {
      _ =>
        return api_error(
          409, "CommercialAdmissionDenied", "lease price estimate is invalid", false,
        )
    } noraise {
      value => value
    }
    let admission = try
      self.commercial_store.admit({
        organization_id: request.submission.organization_id,
        project_id: request.submission.project_id,
        meter: "exclusive-node-second",
        expected_quantity: expected_seconds,
        expected_cost,
        required_capacity_units: 0L,
        required_agreement_types: [],
        now_unix_ms,
      })
    catch {
      _ =>
        return api_error(
          409, "CommercialAdmissionDenied", "organization, project, or commercial policy is not eligible",
          false,
        )
    } noraise {
      value => value
    }
    match admission.kind {
      Allowed => ()
      ApprovalRequired =>
        return api_error(
          409, "CommercialApprovalRequired", "budget policy requires commercial approval before lease start",
          false,
        )
      Blocked =>
        return api_error(
          409,
          "CommercialAdmissionDenied",
          admission.reasons.join("; "),
          false,
        )
    }
  }
  let exclusive_lease_id = "exclusive-\{review.request_id}"
  let intent : @nodelease.ExclusiveNodeLeaseIntent = {
    version: @nodelease.contract_version,
    idempotency_key: "portal-approval-\{review.request_id}",
    lease_id: exclusive_lease_id,
    node_id,
    subject_ref: request.subject_ref,
    unix_username: request.submission.unix_username,
    access_credential_ref: "ssh-cert:\{exclusive_lease_id}",
    starts_unix_ms: request.submission.starts_unix_ms,
    expires_unix_ms: request.submission.expires_unix_ms,
  }
  let exclusive = try exclusive_leases.issue(intent, now_unix_ms) catch {
    @nodelease_store.ExclusiveLeaseStoreError::NodeUnavailable(_) =>
      return api_error(
        409, "NodeUnavailable", "node already has an exclusive lease", false,
      )
    @nodelease_store.ExclusiveLeaseStoreError::IdempotencyConflict(_) =>
      return api_error(
        409, "IdempotencyConflict", "approval identity conflicts with another lease",
        false,
      )
    _ =>
      return api_error(
        409, "ExclusiveLeaseRejected", "exclusive lease reservation was rejected",
        false,
      )
  } noraise {
    value => value
  }
  let approved = try
    portal.review_lease_request(review, Some(exclusive_lease_id), now_unix_ms)
  catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  self.publish_exclusive_lease_directive(exclusive, Cordoned)
  self.operator_audit(
    "portal.lease.approve",
    review.request_id,
    review.evidence_receipt,
  )
  json_reply(200, approved.to_json())
}

///|
async fn ApiService::handle_enterprise_portal(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.portal_store is Some(portal) else {
    return api_error(
      503, "PortalUnavailable", "durable enterprise portal state is unavailable",
      true,
    )
  }
  if path.has_prefix("/v1/portal/operator/") {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthenticated", "valid operator authority is required", false,
      )
    }
    match (verb, path) {
      (Get, "/v1/portal/operator/snapshot") =>
        return json_reply(200, portal.snapshot().to_json())
      (Post, "/v1/portal/operator/memberships") => {
        guard decode_portal_membership(body) is Some(membership) else {
          return api_error(400, "InvalidRequest", "invalid membership", false)
        }
        let persisted = try portal.put_membership(membership) catch {
          error => return portal_error_reply(error)
        } noraise {
          value => value
        }
        self.operator_audit(
          "portal.membership.create",
          persisted.membership_id,
          "portal:membership:\{persisted.membership_id}",
        )
        return json_reply(201, persisted.to_json())
      }
      (Post, "/v1/portal/operator/agreements") => {
        guard decode_portal_agreement(body) is Some(agreement) else {
          return api_error(
            400, "InvalidRequest", "invalid portal agreement", false,
          )
        }
        let persisted = try portal.publish_agreement(agreement) catch {
          error => return portal_error_reply(error)
        } noraise {
          value => value
        }
        self.operator_audit(
          "portal.agreement.publish",
          persisted.agreement_id,
          persisted.rendered_document_hash,
        )
        return json_reply(201, persisted.to_json())
      }
      (Post, "/v1/portal/operator/agreement-executions") =>
        return api_error(
          409, "VerifiedTransportRequired", "portal agreements execute only through the signed qualified-signature callback boundary",
          false,
        )
      (Post, "/v1/portal/operator/lease-reviews") => {
        guard decode_lease_review(body) is Some(review) else {
          return api_error(400, "InvalidRequest", "invalid lease review", false)
        }
        let now = @async.now()
        match review.decision {
          Approve => return self.approve_portal_lease(portal, review, now)
          Reject => {
            if review.node_id is Some(_) {
              return api_error(
                400, "InvalidRequest", "rejection cannot assign a node", false,
              )
            }
            let rejected = try
              portal.review_lease_request(review, None, now)
            catch {
              error => return portal_error_reply(error)
            } noraise {
              value => value
            }
            self.operator_audit(
              "portal.lease.reject",
              review.request_id,
              review.evidence_receipt,
            )
            return json_reply(200, rejected.to_json())
          }
        }
      }
      _ => return api_error(404, "NotFound", "route was not found", false)
    }
  }
  guard self.portal_subject(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    return api_error(
      401, "Unauthenticated", "valid inference authority and verified enterprise identity are required",
      false,
    )
  }
  match (verb, path) {
    (Get, "/v1/portal/self/api-keys") => {
      guard self.access_store is Some(access) else {
        return api_error(
          503, "AccessStoreUnavailable", "API key state is unavailable", true,
        )
      }
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      json_reply(
        200,
        access
        .views_for_subject(view.membership.tenant_ref, subject_ref)
        .to_json(),
      )
    }
    (Post, "/v1/portal/self/api-keys") => {
      guard decode_portal_api_key(body) is Some(intent) else {
        return api_error(
          400, "InvalidRequest", "invalid self-service API key intent", false,
        )
      }
      guard self.access_store is Some(access) else {
        return api_error(
          503, "AccessStoreUnavailable", "API key state is unavailable", true,
        )
      }
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      if !@portal.role_allows(view.membership.roles, Developer) {
        return api_error(
          403, "PortalAccessDenied", "developer role is required", false,
        )
      }
      if self.management_database is Some(_) &&
        !self.commercial_project_exists(
          view.membership.organization_id,
          intent.project_id,
        ) {
        return api_error(
          409, "CommercialProjectRequired", "a project owned by the enterprise organization is required",
          false,
        )
      }
      let now = @async.now()
      let contract_active = match self.contract_document_store {
        Some(contract_store) =>
          contract_store.has_effective_master_lease(
            view.membership.tenant_ref,
            subject_ref,
            now,
          )
        None => false
      }
      let trial = match self.account_store {
        Some(accounts) => accounts.active_trial_for_subject(subject_ref, now)
        None => None
      }
      let trial_active = match trial {
        Some(value) =>
          value.tenant_ref == view.membership.tenant_ref &&
          value.organization_id == view.membership.organization_id &&
          value.project_id == intent.project_id &&
          value.api_key_id is None &&
          intent.expires_unix_ms <= value.expires_unix_ms &&
          intent.maximum_requests <= value.maximum_requests &&
          intent.scopes.all(scope => scope == ModelList || scope == Inference) &&
          intent.allowed_models.length() > 0 &&
          intent.allowed_models.all(model => {
            value.allowed_models.contains(model)
          })
        None => false
      }
      if !contract_active && !trial_active {
        return api_error(
          409, "MasterLeaseRequired", "an effective master lease is required before issuing an API key",
          false,
        )
      }
      let issued = try
        access.issue(
          {
            key_id: intent.key_id,
            tenant_ref: view.membership.tenant_ref,
            subject_ref,
            organization_id: view.membership.organization_id,
            project_id: intent.project_id,
            display_name: intent.display_name,
            scopes: intent.scopes,
            allowed_models: intent.allowed_models,
            expires_unix_ms: intent.expires_unix_ms,
            maximum_requests: intent.maximum_requests,
          },
          now,
        )
      catch {
        _ =>
          return api_error(
            409, "ApiKeyRejected", "self-service API key was rejected", false,
          )
      } noraise {
        value => value
      }
      match trial {
        Some(value) if !contract_active =>
          match self.account_store {
            Some(accounts) =>
              ignore(
                accounts.bind_trial_api_key(
                  value.trial_id,
                  issued.credential.key_id,
                  now,
                ),
              ) catch {
                _ => {
                  ignore(
                    access.revoke_for_subject(
                      issued.credential.key_id,
                      view.membership.tenant_ref,
                      subject_ref,
                      now,
                    ),
                  ) catch {
                    _ => ()
                  }
                  return api_error(
                    409, "TrialApiKeyRejected", "the one-time trial API key was already issued",
                    false,
                  )
                }
              }
            None => ()
          }
        _ => ()
      }
      json_reply(201, issued.public_view().to_json())
    }
    (Post, _) if path.has_prefix("/v1/portal/self/api-keys/") &&
      path.has_suffix(":revoke") => {
      guard self.access_store is Some(access) else {
        return api_error(
          503, "AccessStoreUnavailable", "API key state is unavailable", true,
        )
      }
      let prefix = "/v1/portal/self/api-keys/".length()
      let suffix = ":revoke".length()
      let key_id = path[prefix:path.length() - suffix].to_owned()
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      let revoked = try
        access.revoke_for_subject(
          key_id,
          view.membership.tenant_ref,
          subject_ref,
          @async.now(),
        )
      catch {
        _ => return api_error(404, "NotFound", "API key was not found", false)
      } noraise {
        value => value
      }
      json_reply(200, {
        "key_id": revoked.key_id,
        "revoked_unix_ms": revoked.revoked_unix_ms.to_json(),
      })
    }
    (Get, "/v1/portal/self") => {
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      json_reply(200, view.to_json())
    }
    (Get, "/v1/portal/self/commercial") => {
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      let snapshot = try
        self.commercial_store.snapshot(view.membership.organization_id)
      catch {
        _ =>
          return api_error(
            404, "CommercialStateUnavailable", "organization commercial state is not configured",
            false,
          )
      } noraise {
        value => value
      }
      json_reply(200, snapshot.to_json())
    }
    (Get, "/v1/portal/self/provider-requests") => {
      let view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let snapshot = self.commercial_integrations.snapshot(
        view.membership.organization_id,
      )
      let records = snapshot.records.filter(record => {
        match record.kind {
          Payment | TaxInvoice =>
            @portal.role_allows(view.membership.roles, BillingViewer)
          IdentityVerification =>
            view.membership.roles.contains(OrganizationAdministrator)
          QualifiedSignature =>
            if !@portal.role_allows(view.membership.roles, LegalSigner) {
              false
            } else {
              match
                self.commercial_integrations.record_by_id(record.record_id) {
                Some(raw) =>
                  match raw.entitlement_transaction_ref {
                    Some(link) if link.has_prefix("portal-agreement:") => {
                      let agreement_id = link["portal-agreement:".length():].to_owned()
                      view.agreements.any(agreement => {
                        agreement.agreement_id == agreement_id &&
                        agreement.signer_subject_ref == Some(subject_ref)
                      })
                    }
                    _ => false
                  }
                None => false
              }
            }
        }
      })
      json_reply(200, { ..snapshot, records, }.to_json())
    }
    (Post, "/v1/portal/payment-checkouts") => {
      let intent : ProviderPaymentCheckoutIntent? = try
        @json.from_json(@json.parse(body))
      catch {
        _ => None
      } noraise {
        value => Some(value)
      }
      guard intent is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid payment checkout intent", false,
        )
      }
      self.create_payment_checkout(subject_ref, value)
    }
    (Get, "/v1/portal/self/models") => {
      ignore(
        try portal.self_view(subject_ref) catch {
          error => return portal_error_reply(error)
        } noraise {
          value => value
        },
      )
      guard self.registry is Some(registry) else {
        return json_reply(
          200,
          ([] : Array[@portal.EnterpriseModelSummary]).to_json(),
        )
      }
      let snapshot = registry.snapshot()
      let models : Array[@portal.EnterpriseModelSummary] = [
        for model in snapshot.models if model.state == Approved => {
          let alias_name = snapshot.aliases
            .iter()
            .find_first(value => {
              value.model_id == model.model_id && value.version == model.version
            })
            .map(value => value.name)
          {
            model_id: model.model_id,
            version: model.version,
            alias_name,
            compatible_architectures: model.compatible_architectures,
            minimum_memory_mib: model.minimum_memory_mib,
          }
        }
      ]
      json_reply(200, models.to_json())
    }
    (Post, "/v1/portal/signature-requests") => {
      guard decode_signature_request(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid signature request", false,
        )
      }
      if !@contracts.valid_identifier(request.idempotency_key) {
        return api_error(
          400, "InvalidRequest", "invalid signature request idempotency key", false,
        )
      }
      if !self.commercial_provider_adapter_ready() {
        return api_error(
          503, "CommercialProviderUnavailable", "qualified-signature provider adapter is not ready",
          true,
        )
      }
      let self_view = try portal.self_view(subject_ref) catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      let existing = self_view.agreements
        .iter()
        .find_first(value => value.agreement_id == request.agreement_id)
      // Forward-repair a crash after the portal transition but before the
      // integration outbox commit. A same signer can safely requeue the stable
      // agreement generation even if the browser generated a new retry key.
      let persisted = match existing {
        Some(value) if value.state == SignatureRequested &&
          value.signer_subject_ref == Some(subject_ref) => value
        _ =>
          try
            portal.request_signature(subject_ref, request, @async.now())
          catch {
            error => return portal_error_reply(error)
          } noraise {
            value => value
          }
      }
      let stable_request_key = "\{persisted.agreement_id}:\{persisted.generation}:\{persisted.rendered_document_hash}"
      let digest = provider_request_digest(
        persisted.organization_id,
        stable_request_key,
      )
      let queued = try
        self.queue_provider_record({
          record_id: "signature-\{digest}",
          organization_id: persisted.organization_id,
          kind: QualifiedSignature,
          provider: self.commercial_provider_name.unwrap_or(""),
          environment: self.commercial_provider_environment.unwrap_or(""),
          external_ref: "envelope-\{digest}",
          state: Pending,
          expected_amount_minor: None,
          currency: None,
          money_scale: None,
          expected_document_hash: Some(persisted.rendered_document_hash),
          entitlement_transaction_ref: Some(
            "portal-agreement:\{persisted.agreement_id}",
          ),
          created_unix_ms: persisted.updated_unix_ms,
          updated_unix_ms: persisted.updated_unix_ms,
        })
      catch {
        _ =>
          return api_error(
            503, "CommercialPersistenceFailed", "signature request was retained but provider dispatch could not be queued",
            true,
          )
      } noraise {
        value => value
      }
      ignore(queued)
      json_reply(202, persisted.to_json())
    }
    (Post, "/v1/portal/lease-requests") => {
      guard decode_lease_submission(body) is Some(submission) else {
        return api_error(400, "InvalidRequest", "invalid lease request", false)
      }
      let persisted = try
        portal.submit_lease_request(subject_ref, submission, @async.now())
      catch {
        error => return portal_error_reply(error)
      } noraise {
        value => value
      }
      json_reply(201, persisted.to_json())
    }
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}
