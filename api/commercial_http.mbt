///|
fn commercial_management_path(path : String) -> Bool {
  path.has_prefix("/v1/commercial/")
}

///|
priv struct CommercialRateRequest {
  event_id : String
  entry_id : String
  rate : @commercial.RateCard
  recorded_unix_ms : Int64
} derive(FromJson)

///|
priv struct CommercialFinalizeRequest {
  period_id : String
  organization_id : String
  started_unix_ms : Int64
  ended_unix_ms : Int64
  billing_timezone : String
  currency : String
  scale : Int
  finalized_by : String
  finalized_unix_ms : Int64
} derive(FromJson)

///|
priv struct CommercialAdjustmentRequest {
  adjustment_id : String
  organization_id : String
  linked_entry_id : String
  kind : @commercial.LedgerEntryKind
  amount : @commercial.FixedMoney
  reason : String
  recorded_unix_ms : Int64
} derive(FromJson)

///|
priv struct CommercialCommitmentApprovalRequest {
  organization_id : String
  commitment_id : String
  approver : String
  now_unix_ms : Int64
} derive(FromJson)

///|
priv struct CommercialAgreementTransitionRequest {
  organization_id : String
  agreement_id : String
  actor_user_id : String
  next : @commercial.AgreementState
  updated_unix_ms : Int64
} derive(FromJson)

///|
priv struct CommercialExportRequest {
  organization_id : String
  actor_user_id : String
  filter_project_id : String?
  generated_unix_ms : Int64
} derive(FromJson)

///|
fn decode_organization(body : String) -> @commercial.Organization? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_cost_center(body : String) -> @commercial.CostCenter? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_project(body : String) -> @commercial.Project? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_role_grant(body : String) -> @commercial.RoleGrant? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_usage_observation(body : String) -> @commercial.UsageObservation? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_rate_request(body : String) -> CommercialRateRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_finalize_request(body : String) -> CommercialFinalizeRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_adjustment_request(body : String) -> CommercialAdjustmentRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_budget(body : String) -> @commercial.Budget? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_commercial_quota(body : String) -> @commercial.Quota? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_commercial_admission(body : String) -> @commercial.AdmissionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_commitment(body : String) -> @commercial.CapacityCommitment? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_commitment_approval(
  body : String,
) -> CommercialCommitmentApprovalRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_consumption(body : String) -> @commercial.EntitlementConsumption? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_agreement_template(body : String) -> @commercial.AgreementTemplate? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_clickwrap(body : String) -> @commercial.ClickwrapAcceptance? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_agreement(body : String) -> @commercial.Agreement? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_agreement_transition(
  body : String,
) -> CommercialAgreementTransitionRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_signature_callback(body : String) -> @commercial.SignatureCallback? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_external_record(
  body : String,
) -> @commercial_integrations.ExternalRecord? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_external_callback(
  body : String,
) -> @commercial_integrations.ExternalCallback? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_export_request(body : String) -> CommercialExportRequest? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn commercial_rejected(message : String) -> HttpReply {
  api_error(409, "CommercialRejected", message, false)
}

///|
fn commercial_organization_path(path : String) -> (String, String)? {
  let prefix = "/v1/commercial/organizations/"
  if !path.has_prefix(prefix) {
    return None
  }
  let remainder = path[prefix.length():].to_owned()
  for suffix in ["/snapshot", "/summary", "/integrations"] {
    if remainder.has_suffix(suffix) && remainder.length() > suffix.length() {
      return Some(
        (
          remainder[:remainder.length() - suffix.length()].to_owned(),
          suffix[1:].to_owned(),
        ),
      )
    }
  }
  None
}

///|
async fn ApiService::persist_commercial_state(self : ApiService) -> Unit {
  guard self.management_database is Some(database) else { return }
  let commercial = self.commercial_store.durable_snapshot()
  let integrations = self.commercial_integrations.durable_snapshot()
  database.save_opaque_snapshots([
    (
      "commercial",
      @commercial.snapshot_schema_version,
      commercial.to_json().stringify(),
    ),
    (
      "commercial_integrations",
      @commercial_integrations.integration_schema_version,
      integrations.to_json().stringify(),
    ),
  ])
}

///|
async fn ApiService::handle_commercial_management(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if !bearer_authorized(headers, self.operator_token) {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  if verb == Get &&
    commercial_organization_path(path) is Some((organization_id, view)) {
    if view == "integrations" {
      return json_reply(
        200,
        self.commercial_integrations.snapshot(organization_id).to_json(),
      )
    }
    if view == "summary" {
      let summary = try
        self.commercial_store.summary(organization_id, "CNY", 2, @async.now())
      catch {
        _ => return commercial_rejected("commercial summary is unavailable")
      } noraise {
        value => value
      }
      return json_reply(200, summary.to_json())
    }
    let snapshot = try self.commercial_store.snapshot(organization_id) catch {
      _ => return commercial_rejected("commercial snapshot is unavailable")
    } noraise {
      value => value
    }
    return json_reply(200, snapshot.to_json())
  }
  let before_commercial = self.commercial_store.durable_snapshot()
  let before_integrations = self.commercial_integrations.durable_snapshot()
  let reply = match (verb, path) {
    (Post, "/v1/commercial/organizations") => {
      guard decode_organization(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid organization", false)
      }
      self.commercial_store.add_organization(value) catch {
        _ => return commercial_rejected("organization was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/cost-centers") => {
      guard decode_cost_center(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid cost center", false)
      }
      self.commercial_store.add_cost_center(value) catch {
        _ => return commercial_rejected("cost center was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/projects") => {
      guard decode_project(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid project", false)
      }
      self.commercial_store.add_project(value) catch {
        _ => return commercial_rejected("project was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/role-grants") => {
      guard decode_role_grant(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid role grant", false)
      }
      self.commercial_store.grant_role(value) catch {
        _ => return commercial_rejected("role grant was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/usage") => {
      guard decode_usage_observation(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid usage observation", false,
        )
      }
      let result = try self.commercial_store.ingest_usage(value) catch {
        _ => return commercial_rejected("usage observation was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, result.to_json())
    }
    (Post, "/v1/commercial/usage:rate") => {
      guard decode_rate_request(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid rating request", false)
      }
      let (entry, result) = try
        self.commercial_store.rate_usage(
          value.event_id,
          value.entry_id,
          value.rate,
          value.recorded_unix_ms,
        )
      catch {
        _ => return commercial_rejected("usage rating was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, { "entry": entry.to_json(), "result": result.to_json() })
    }
    (Post, "/v1/commercial/periods:finalize") => {
      guard decode_finalize_request(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid finalization request", false,
        )
      }
      let period = try
        self.commercial_store.finalize_period(
          value.period_id,
          value.organization_id,
          value.started_unix_ms,
          value.ended_unix_ms,
          value.billing_timezone,
          value.currency,
          value.scale,
          value.finalized_by,
          value.finalized_unix_ms,
        )
      catch {
        _ => return commercial_rejected("period finalization was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, period.to_json())
    }
    (Post, "/v1/commercial/adjustments") => {
      guard decode_adjustment_request(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid adjustment", false)
      }
      let entry = try
        self.commercial_store.append_adjustment(
          value.adjustment_id,
          value.organization_id,
          value.linked_entry_id,
          value.kind,
          value.amount,
          value.reason,
          value.recorded_unix_ms,
        )
      catch {
        _ => return commercial_rejected("adjustment was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, entry.to_json())
    }
    (Post, "/v1/commercial/budgets") => {
      guard decode_budget(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid budget", false)
      }
      self.commercial_store.add_budget(value) catch {
        _ => return commercial_rejected("budget was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/quotas") => {
      guard decode_commercial_quota(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid commercial quota", false,
        )
      }
      self.commercial_store.add_quota(value) catch {
        _ => return commercial_rejected("commercial quota was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/admission:decide") => {
      guard decode_commercial_admission(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid admission request", false,
        )
      }
      let decision = try self.commercial_store.admit(value) catch {
        _ => return commercial_rejected("commercial admission failed closed")
      } noraise {
        accepted => accepted
      }
      json_reply(200, decision.to_json())
    }
    (Post, "/v1/commercial/commitments") => {
      guard decode_commitment(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid commitment", false)
      }
      self.commercial_store.add_commitment(value) catch {
        _ => return commercial_rejected("commitment was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/commitments:approve") => {
      guard decode_commitment_approval(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid commitment approval", false,
        )
      }
      let commitment = try
        self.commercial_store.approve_commitment(
          value.organization_id,
          value.commitment_id,
          value.approver,
          value.now_unix_ms,
        )
      catch {
        _ => return commercial_rejected("commitment approval was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(200, commitment.to_json())
    }
    (Post, "/v1/commercial/entitlements:consume") => {
      guard decode_consumption(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid entitlement consumption", false,
        )
      }
      let result = try self.commercial_store.consume_entitlement(value) catch {
        _ => return commercial_rejected("entitlement consumption was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, result.to_json())
    }
    (Post, "/v1/commercial/agreement-templates") => {
      guard decode_agreement_template(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid agreement template", false,
        )
      }
      self.commercial_store.register_agreement_template(value) catch {
        _ => return commercial_rejected("agreement template was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/acceptances") => {
      guard decode_clickwrap(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid acceptance evidence", false,
        )
      }
      let result = try self.commercial_store.accept_clickwrap(value) catch {
        _ => return commercial_rejected("acceptance evidence was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, result.to_json())
    }
    (Post, "/v1/commercial/agreements") => {
      guard decode_agreement(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid agreement", false)
      }
      self.commercial_store.create_agreement(value) catch {
        _ => return commercial_rejected("agreement was rejected")
      }
      json_reply(201, value.to_json())
    }
    (Post, "/v1/commercial/agreements:transition") => {
      guard decode_agreement_transition(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid agreement transition", false,
        )
      }
      let agreement = try
        self.commercial_store.transition_agreement(
          value.organization_id,
          value.agreement_id,
          value.actor_user_id,
          value.next,
          value.updated_unix_ms,
        )
      catch {
        _ => return commercial_rejected("agreement transition was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(200, agreement.to_json())
    }
    (Post, "/v1/commercial/signature-callbacks") => {
      guard decode_signature_callback(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid signature callback", false,
        )
      }
      let (agreement, result) = try
        self.commercial_store.reconcile_signature_callback(value)
      catch {
        _ => return commercial_rejected("signature callback was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(200, {
        "agreement": agreement.to_json(),
        "result": result.to_json(),
      })
    }
    (Post, "/v1/commercial/external-records") => {
      guard decode_external_record(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid external record", false,
        )
      }
      let result = try self.commercial_integrations.register(value) catch {
        _ => return commercial_rejected("external record was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(201, result.to_json())
    }
    (Post, "/v1/commercial/external-callbacks") => {
      guard decode_external_callback(body) is Some(value) else {
        return api_error(
          400, "InvalidRequest", "invalid external callback", false,
        )
      }
      let (record, result) = try
        self.commercial_integrations.reconcile_callback(value)
      catch {
        _ => return commercial_rejected("external callback was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(200, { "record": record.to_json(), "result": result.to_json() })
    }
    (Post, "/v1/commercial/exports") => {
      guard decode_export_request(body) is Some(value) else {
        return api_error(400, "InvalidRequest", "invalid export request", false)
      }
      let commercial_export = try
        self.commercial_store.export_ledger_csv(
          value.organization_id,
          value.actor_user_id,
          value.filter_project_id,
          value.generated_unix_ms,
        )
      catch {
        _ => return commercial_rejected("commercial export was rejected")
      } noraise {
        accepted => accepted
      }
      json_reply(200, commercial_export.to_json())
    }
    _ => api_error(404, "NotFound", "commercial route was not found", false)
  }
  if verb != Get && reply.status >= 200 && reply.status < 300 {
    self.persist_commercial_state() catch {
      _ => {
        ignore(
          self.commercial_store.replace_from_durable_snapshot(before_commercial),
        )
        ignore(
          self.commercial_integrations.replace_from_durable_snapshot(
            before_integrations,
          ),
        )
        return api_error(
          503, "CommercialPersistenceFailed", "commercial mutation was rolled back because durable commit failed",
          true,
        )
      }
    }
  }
  reply
}
