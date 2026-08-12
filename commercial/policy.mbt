///|
pub fn CommercialStore::add_budget(
  self : CommercialStore,
  budget : Budget,
) -> Unit raise CommercialError {
  ignore(self.require_organization(budget.organization_id))
  ignore(
    money(budget.limit.minor_units, budget.limit.currency, budget.limit.scale),
  )
  match budget.project_id {
    Some(project_id) =>
      ignore(self.require_project(budget.organization_id, project_id))
    None => ()
  }
  if !safe_identifier(budget.budget_id) ||
    budget.limit.minor_units <= 0L ||
    budget.warning_percent <= 0 ||
    budget.warning_percent > 100 ||
    budget.grace_minor_units < 0L ||
    budget.effective_from_unix_ms <= 0L ||
    budget.effective_until_unix_ms <= budget.effective_from_unix_ms {
    raise InvalidInput("invalid budget")
  }
  if self.budgets.contains(budget.budget_id) {
    raise AlreadyExists("budget")
  }
  self.budgets[budget.budget_id] = budget
}

///|
pub fn CommercialStore::add_quota(
  self : CommercialStore,
  quota : Quota,
) -> Unit raise CommercialError {
  ignore(self.require_organization(quota.organization_id))
  match quota.project_id {
    Some(project_id) =>
      ignore(self.require_project(quota.organization_id, project_id))
    None => ()
  }
  if !safe_identifier(quota.quota_id) ||
    !safe_identifier(quota.meter) ||
    quota.maximum_quantity <= 0L ||
    quota.period_started_unix_ms <= 0L ||
    quota.period_ended_unix_ms <= quota.period_started_unix_ms {
    raise InvalidInput("invalid quota")
  }
  if self.quotas.contains(quota.quota_id) {
    raise AlreadyExists("quota")
  }
  self.quotas[quota.quota_id] = quota
}

///|
fn warning_threshold(limit : Int64, percent : Int) -> Int64 {
  limit / 100L * Int64::from_int(percent) +
  limit % 100L * Int64::from_int(percent) / 100L
}

///|
fn CommercialStore::spent_for_budget(
  self : CommercialStore,
  budget : Budget,
) -> FixedMoney raise CommercialError {
  let mut spent = zero_like(budget.limit)
  for entry in self.entries.values() {
    if entry.organization_id == budget.organization_id &&
      (budget.project_id is None || budget.project_id == Some(entry.project_id)) &&
      entry.service_ended_unix_ms >= budget.effective_from_unix_ms &&
      entry.service_started_unix_ms < budget.effective_until_unix_ms {
      spent = spent.add(entry.amount)
    }
  }
  spent
}

///|
fn CommercialStore::quota_usage(
  self : CommercialStore,
  quota : Quota,
) -> Int64 raise CommercialError {
  let mut total = 0L
  for observation in self.observations.values() {
    if observation.organization_id == quota.organization_id &&
      (
        quota.project_id is None ||
        quota.project_id == Some(observation.project_id)
      ) &&
      observation.meter == quota.meter &&
      observation.started_unix_ms >= quota.period_started_unix_ms &&
      observation.ended_unix_ms <= quota.period_ended_unix_ms {
      total = checked_add_int64(total, observation.quantity)
    }
  }
  total
}

///|
pub fn CommercialStore::add_commitment(
  self : CommercialStore,
  commitment : CapacityCommitment,
) -> Unit raise CommercialError {
  ignore(self.require_organization(commitment.organization_id))
  if !safe_identifier(commitment.commitment_id) ||
    !safe_identifier(commitment.cluster_id) ||
    !safe_identifier(commitment.gpu_class) ||
    !safe_identifier(commitment.service_mode) ||
    !safe_identifier(commitment.created_by) ||
    commitment.capacity_units <= 0L ||
    commitment.effective_from_unix_ms <= 0L ||
    commitment.effective_until_unix_ms <= commitment.effective_from_unix_ms ||
    commitment.state != Proposed ||
    commitment.approved_by is Some(_) {
    raise InvalidInput("invalid proposed capacity commitment")
  }
  if self.commitments.contains(commitment.commitment_id) {
    raise AlreadyExists("capacity commitment")
  }
  self.commitments[commitment.commitment_id] = commitment
}

///|
pub fn CommercialStore::approve_commitment(
  self : CommercialStore,
  organization_id : String,
  commitment_id : String,
  approver : String,
  now_unix_ms : Int64,
) -> CapacityCommitment raise CommercialError {
  let commitment = match self.commitments.get(commitment_id) {
    Some(value) => value
    None => raise NotFound("capacity commitment")
  }
  if commitment.organization_id != organization_id {
    raise TenantMismatch
  }
  if commitment.state != Proposed ||
    now_unix_ms >= commitment.effective_until_unix_ms {
    raise InvalidTransition("capacity commitment")
  }
  if commitment.created_by == approver {
    raise SeparationOfDuties("commitment creator cannot approve it")
  }
  if !self.has_permission(
      organization_id,
      approver,
      ApproveCommitment,
      now_unix_ms,
    ) {
    raise PermissionDenied("procurement approval required")
  }
  let state = if now_unix_ms >= commitment.effective_from_unix_ms {
    ActiveCommitment
  } else {
    Approved
  }
  let updated = { ..commitment, approved_by: Some(approver), state }
  self.commitments[commitment_id] = updated
  updated
}

///|
pub fn CommercialStore::remaining_capacity(
  self : CommercialStore,
  commitment_id : String,
) -> Int64 raise CommercialError {
  let commitment = match self.commitments.get(commitment_id) {
    Some(value) => value
    None => raise NotFound("capacity commitment")
  }
  let mut consumed = 0L
  for item in self.consumptions.values() {
    if item.commitment_id == commitment_id {
      consumed = checked_add_int64(consumed, item.quantity)
    }
  }
  commitment.capacity_units - consumed
}

///|
pub fn CommercialStore::consume_entitlement(
  self : CommercialStore,
  consumption : EntitlementConsumption,
) -> IdempotencyResult raise CommercialError {
  if !safe_identifier(consumption.consumption_id) ||
    !safe_identifier(consumption.workload_id) ||
    consumption.quantity <= 0L ||
    consumption.consumed_unix_ms <= 0L {
    raise InvalidInput("invalid entitlement consumption")
  }
  match self.consumptions.get(consumption.consumption_id) {
    Some(existing) =>
      if existing == consumption {
        Replayed
      } else {
        raise IdempotencyConflict("entitlement consumption changed")
      }
    None => {
      let commitment = match self.commitments.get(consumption.commitment_id) {
        Some(value) => value
        None => raise NotFound("capacity commitment")
      }
      if commitment.organization_id != consumption.organization_id {
        raise TenantMismatch
      }
      if (commitment.state != Approved && commitment.state != ActiveCommitment) ||
        consumption.consumed_unix_ms < commitment.effective_from_unix_ms ||
        consumption.consumed_unix_ms >= commitment.effective_until_unix_ms {
        raise AdmissionDenied("capacity commitment is not active")
      }
      if consumption.quantity >
        self.remaining_capacity(consumption.commitment_id) {
        raise AdmissionDenied("capacity commitment is exhausted")
      }
      self.consumptions[consumption.consumption_id] = consumption
      if self.remaining_capacity(consumption.commitment_id) == 0L {
        self.commitments[commitment.commitment_id] = {
          ..commitment,
          state: Exhausted,
        }
      }
      Created
    }
  }
}

///|
fn CommercialStore::matching_commitment(
  self : CommercialStore,
  organization_id : String,
  required_units : Int64,
  now_unix_ms : Int64,
) -> String? raise CommercialError {
  let candidates = self.commitments
    .values()
    .filter(commitment => {
      commitment.organization_id == organization_id &&
      (commitment.state == Approved || commitment.state == ActiveCommitment) &&
      now_unix_ms >= commitment.effective_from_unix_ms &&
      now_unix_ms < commitment.effective_until_unix_ms
    })
    .to_array()
  candidates.sort_by((left, right) => {
    let expiry = left.effective_until_unix_ms.compare(
      right.effective_until_unix_ms,
    )
    if expiry == 0 {
      left.commitment_id.compare(right.commitment_id)
    } else {
      expiry
    }
  })
  for commitment in candidates {
    if self.remaining_capacity(commitment.commitment_id) >= required_units {
      return Some(commitment.commitment_id)
    }
  }
  None
}

///|
pub fn CommercialStore::admit(
  self : CommercialStore,
  request : AdmissionRequest,
) -> AdmissionDecision raise CommercialError {
  let organization = self.require_organization(request.organization_id)
  ignore(self.require_project(request.organization_id, request.project_id))
  ignore(
    money(
      request.expected_cost.minor_units,
      request.expected_cost.currency,
      request.expected_cost.scale,
    ),
  )
  if request.expected_quantity < 0L ||
    request.expected_cost.minor_units < 0L ||
    request.required_capacity_units < 0L ||
    request.now_unix_ms <= 0L {
    raise InvalidInput("invalid admission estimate")
  }
  let reasons : Array[String] = []
  let mut approval_required = false
  if organization.state != Active {
    reasons.push("organization is not active")
  }
  if organization.verification_ref is None {
    reasons.push("organization verification is incomplete")
  }
  for agreement_type in request.required_agreement_types {
    if !self.agreement_type_satisfied(request.organization_id, agreement_type) {
      reasons.push("missing agreement:\{agreement_type}")
    }
  }
  for quota in self.quotas.values() {
    if quota.organization_id == request.organization_id &&
      (quota.project_id is None || quota.project_id == Some(request.project_id)) &&
      quota.meter == request.meter &&
      request.now_unix_ms >= quota.period_started_unix_ms &&
      request.now_unix_ms < quota.period_ended_unix_ms {
      let used = self.quota_usage(quota)
      if request.expected_quantity > quota.maximum_quantity - used {
        reasons.push("quota exceeded:\{quota.quota_id}")
      }
    }
  }
  for budget in self.budgets.values() {
    if budget.organization_id == request.organization_id &&
      (
        budget.project_id is None ||
        budget.project_id == Some(request.project_id)
      ) &&
      request.now_unix_ms >= budget.effective_from_unix_ms &&
      request.now_unix_ms < budget.effective_until_unix_ms {
      ensure_same_money_unit(budget.limit, request.expected_cost)
      let projected = self.spent_for_budget(budget).add(request.expected_cost)
      let hard_limit = checked_add_int64(
        budget.limit.minor_units,
        budget.grace_minor_units,
      )
      if budget.hard_stop && projected.minor_units > hard_limit {
        reasons.push("budget hard stop:\{budget.budget_id}")
      } else if projected.minor_units >=
        warning_threshold(budget.limit.minor_units, budget.warning_percent) {
        match budget.warning_action {
          Notify => ()
          RequireApproval => approval_required = true
          BlockNewWork =>
            reasons.push("budget policy block:\{budget.budget_id}")
        }
      }
    }
  }
  let commitment_id = if request.required_capacity_units > 0L {
    self.matching_commitment(
      request.organization_id,
      request.required_capacity_units,
      request.now_unix_ms,
    )
  } else {
    None
  }
  if request.required_capacity_units > 0L && commitment_id is None {
    reasons.push("capacity entitlement unavailable")
  }
  if !reasons.is_empty() {
    { kind: Blocked, reasons, matching_commitment_id: commitment_id }
  } else if approval_required {
    {
      kind: ApprovalRequired,
      reasons: ["budget warning threshold reached"],
      matching_commitment_id: commitment_id,
    }
  } else {
    { kind: Allowed, reasons: [], matching_commitment_id: commitment_id }
  }
}
