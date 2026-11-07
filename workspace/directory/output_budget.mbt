///|
/// Synchronizes request budgets on existing active leases derived from an
/// exact policy receipt. It never creates access, renews a lease, resets usage,
/// or changes concurrency. Persistence is atomic within the workspace domain.
pub async fn FileWorkspaceDirectory::sync_policy_output_budget(
  self : FileWorkspaceDirectory,
  tenant_ref : String,
  policy_receipt : String,
  output_tokens : Int32,
  now : Int64,
  input_bytes? : Int32,
) -> Int32 {
  if output_tokens <= 0 || output_tokens > 131072 {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "invalid output budget",
    )
  }
  if input_bytes is Some(value) && (value <= 0 || value > 65536) {
    raise @workspace.WorkspaceDirectoryError::InvalidDirectoryState(
      "invalid input budget",
    )
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let previous = self.leases.copy()
  errdefer {
    self.leases = previous
  }
  let mut changed = 0
  for id, lease in previous {
    if lease.tenant_ref != tenant_ref ||
      lease.policy_receipt != policy_receipt ||
      lease.state != Active ||
      now < lease.starts_unix_ms ||
      now >= lease.expires_unix_ms {
      continue
    }
    guard user_for_subject(self.users, lease.subject_ref) is Some(user) &&
      self.has_grant_for_lease_unlocked(user, lease, now) else {
      continue
    }
    let capabilities = lease.limits.capabilities.map(limit => {
      if limit.capability == TextGenerate {
        {
          ..limit,
          max_output_units_per_request: output_tokens,
          max_input_units_per_request: input_bytes.unwrap_or(
            limit.max_input_units_per_request,
          ),
        }
      } else {
        limit
      }
    })
    let updated = { ..lease, limits: { ..lease.limits, capabilities, }, }
    @workspace.validate_workspace_lease(updated)
    if updated != lease {
      self.leases[id] = updated
      changed += 1
    }
  }
  if changed > 0 {
    self.persist()
  }
  changed
}
