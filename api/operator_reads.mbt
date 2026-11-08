///|
fn operator_read_path(path : String) -> Bool {
  [
    "/v1/operator/list-page", "/v1/operator/access-context", "/v1/operator/node-ownership",
  ].contains(path)
}

///|
/// Bind a cursor to the filtered, ordered identities and its query. The digest
/// detects insert/delete/reorder between pages; it confers no authority.
fn operator_page_window(
  query : @operator_read.PageQuery,
  identities : Array[String],
) -> (Int32, String)? {
  let fingerprint = digest_hex(
    Json([
      query.list,
      query.query.trim().to_owned().to_lower(),
      query.account_id,
      Json(identities).stringify(),
    ]).stringify(),
  )
  if query.cursor == "" {
    return Some((0, fingerprint))
  }
  let parts = query.cursor.split(":").to_array()
  guard parts.length() == 2 && parts[1] == fingerprint else { return None }
  let offset = @string.parse_int(parts[0]) catch { _ => return None }
  guard offset >= 0 && offset % 25 == 0 && offset < identities.length() else {
    return None
  }
  Some((offset, fingerprint))
}

///|
fn operator_page_reply(
  items : Array[Json],
  total : Int32,
  offset : Int32,
  fingerprint : String,
  summary~ : Map[String, Int32] = Map([]),
) -> HttpReply {
  let page : @operator_read.ReadPage = {
    items,
    total,
    page: offset / 25,
    previous_cursor: if offset == 0 {
      ""
    } else {
      "\{offset - 25}:\{fingerprint}"
    },
    next_cursor: if offset + 25 >= total {
      ""
    } else {
      "\{offset + 25}:\{fingerprint}"
    },
    summary,
  }
  json_reply(200, Json(page))
}

///|
fn operator_cursor_changed() -> HttpReply {
  api_error(409, "ListChanged", "records changed; refresh the first page", true)
}

///|
/// Audit is append-only. Pin the highest sequence for this traversal so active
/// traffic cannot keep forcing an operator back to the newest page.
fn operator_audit_window(
  query : @operator_read.PageQuery,
  all : Array[@contracts.AuditEvent],
) -> (Array[@contracts.AuditEvent], Int32, String)? {
  let search = query.query.trim().to_owned().to_lower()
  let binding = digest_hex(
    Json([query.list, search, query.account_id]).stringify(),
  )
  let (offset, upper) = if query.cursor == "" {
    (0, all.fold(init=0L, (highest, event) => highest.max(event.sequence)))
  } else {
    let parts = query.cursor.split(":").to_array()
    guard parts.length() == 3 && parts[2] == binding else { return None }
    let offset = @string.parse_int(parts[0]) catch { _ => return None }
    let upper = @string.parse_int64(parts[1]) catch { _ => return None }
    guard offset >= 0 && offset % 25 == 0 && upper >= 0L else { return None }
    (offset, upper)
  }
  let events = all
    .rev()
    .filter(event => {
      event.sequence <= upper &&
      (query.list != "request-receipts" || event.action.has_prefix("workload.")) &&
      (
        search == "" ||
        "\{event.actor} \{event.action} \{event.target} \{event.result} \{event.correlation_receipt}"
        .to_lower()
        .contains(search)
      )
    })
  if offset > 0 && offset >= events.length() {
    return None
  }
  Some((events, offset, "\{upper}:\{binding}"))
}

///|
async fn ApiService::handle_operator_reads(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if verb != Post {
    return api_error(
      405, "MethodNotAllowed", "operator reads require POST", false,
    )
  }
  let query : @operator_read.PageQuery = if path == "/v1/operator/list-page" {
    try @json.from_json(@json.parse(body)) catch {
      _ => return api_error(400, "InvalidRequest", "invalid page query", false)
    } noraise {
      value => value
    }
  } else {
    { list: "", query: "", account_id: "", cursor: "", }
  }
  let audit = query.list == "audit-events" || query.list == "request-receipts"
  if !(if audit {
      self.audit_authorized(headers)
    } else {
      self.operator_authorized(headers)
    }) {
    return api_error(
      401, "Unauthenticated", "valid list authority is required", false,
    )
  }
  if path == "/v1/operator/node-ownership" {
    return self.operator_node_ownership()
  }
  if query.query.length() > 256 ||
    query.cursor.length() > 2048 ||
    query.account_id.length() > 256 {
    return api_error(
      400, "InvalidRequest", "page query exceeds its limit", false,
    )
  }
  let search = query.query.trim().to_owned().to_lower()
  let matches = (text : String) => {
    search == "" || text.to_lower().contains(search)
  }
  if audit {
    let all = self.store.audit_events()
    guard operator_audit_window(query, all)
      is Some((events, offset, fingerprint)) else {
      return operator_cursor_changed()
    }
    return operator_page_reply(
      events[offset:(offset + 25).min(events.length())].map(event => Json(event)),
      events.length(),
      offset,
      fingerprint,
      summary={
        "requests": all.count_if(event => event.action.has_prefix("workload.")),
        "errors": all.count_if(event => {
          event.action.has_prefix("workload.") &&
          (event.action == "workload.fail" || event.result != "accepted")
        }),
        "changes": all.length().min(20),
      },
    )
  }
  guard self.account_store is Some(accounts) &&
    self.workspace_directory is Some(directory) else {
    return api_error(
      503, "WorkspaceUnavailable", "operator directory is unavailable", true,
    )
  }
  let now = @async.now()
  let workspace = directory.snapshot(now)
  let account_views = accounts.views()
  if path == "/v1/operator/access-context" {
    // Choice metadata has no receipts, history, grants or membership milestones.
    // It is separate from the paged tables so off-page people remain selectable.
    return json_reply(200, {
      "people": Json(
        account_views.map(account => {
          "account_id": Json(account.account_id),
          "subject_ref": Json(account.subject_ref),
          "display_name": Json(account.display_name),
          "email": Json(account.email),
          "roles": Json(account.roles),
          "state": Json(account.state),
        }),
      ),
      "workspace_people": Json(
        workspace.users.map(user => {
          "user_id": Json(user.user_id),
          "subject_ref": Json(user.subject_ref),
        }),
      ),
      "leases": Json(workspace.leases),
    })
  }
  match query.list {
    "accounts" => {
      let rows = account_views.filter(account => {
        matches(
          "\{account.account_id} \{account.display_name} \{account.email} \{Json(account.roles).stringify()}",
        )
      })
      rows.sort_by_key(account => account.account_id)
      guard operator_page_window(query, rows.map(row => row.account_id))
        is Some((offset, fingerprint)) else {
        return operator_cursor_changed()
      }
      operator_page_reply(
        rows[offset:(offset + 25).min(rows.length())].map(row => Json(row)),
        rows.length(),
        offset,
        fingerprint,
      )
    }
    "workspace-profiles" => {
      let rows = workspace.users.filter(user => {
        matches("\{user.user_id} \{user.display_name} \{user.email}")
      })
      rows.sort_by_key(user => user.user_id)
      guard operator_page_window(query, rows.map(row => row.user_id))
        is Some((offset, fingerprint)) else {
        return operator_cursor_changed()
      }
      operator_page_reply(
        rows[offset:(offset + 25).min(rows.length())].map(user => {
          "user": Json(user),
          "grant_count": Json(
            workspace.access_grants.count_if(grant => {
              grant.user_id == user.user_id
            }),
          ),
        }),
        rows.length(),
        offset,
        fingerprint,
      )
    }
    "access-grants" => {
      let rows = workspace.access_grants.filter(grant => {
        matches("\{grant.user_id} \{grant.grant_id} \{grant.tenant_ref}")
      })
      rows.sort_by_key(grant => grant.grant_id)
      guard operator_page_window(query, rows.map(row => row.grant_id))
        is Some((offset, fingerprint)) else {
        return operator_cursor_changed()
      }
      operator_page_reply(
        rows[offset:(offset + 25).min(rows.length())].map(row => Json(row)),
        rows.length(),
        offset,
        fingerprint,
      )
    }
    "access-records" => {
      guard self.portal_store is Some(portal) else {
        return api_error(
          503, "PortalUnavailable", "membership directory is unavailable", true,
        )
      }
      let selected = account_views
        .iter()
        .find_first(account => {
          account.account_id == query.account_id &&
          @account.role_allows(account.roles, EnterpriseUser)
        })
      guard selected is Some(account) else {
        return operator_page_reply([], 0, 0, "")
      }
      let organizations = self.commercial_store.durable_snapshot().commercial.organizations
      let rows = portal.snapshot().memberships.filter(membership => {
        membership.subject_ref == account.subject_ref &&
        matches(
          membership.organization_id +
          " " +
          organizations
          .iter()
          .find_first(org => org.organization_id == membership.organization_id)
          .map_or("", org => org.display_name),
        )
      })
      rows.sort_by_key(row => row.membership_id)
      guard operator_page_window(query, rows.map(row => row.membership_id))
        is Some((offset, fingerprint)) else {
        return operator_cursor_changed()
      }
      let items : Array[Json] = []
      // The costly contract/model readiness projection runs only for this page,
      // after filtering by person and company, never for every membership.
      for membership in rows[offset:(offset + 25).min(rows.length())] {
        items.push(
          self.access_package_view_for_membership(
            account, membership, workspace, now,
          ),
        )
      }
      operator_page_reply(items, rows.length(), offset, fingerprint)
    }
    _ => api_error(400, "InvalidRequest", "unknown operator list", false)
  }
}

///|
/// Desired ownership is a cheap ledger projection, not a runtime health probe.
async fn ApiService::operator_node_ownership(self : ApiService) -> HttpReply {
  guard self.deployment_store is Some(store) else { return json_reply(200, []) }
  let organizations = self.commercial_store.durable_snapshot().commercial.organizations
  let rows : Array[Json] = []
  for
    service in store
    .services()
    .filter(service => {
      service.reserves_company_node() || service.holds_resources()
    }) {
    for node_id in service.node_ids {
      rows.push({
        "node_id": Json(node_id),
        "service_id": Json(service.service_id),
        "tenant_ref": Json(service.owner.tenant_ref),
        "organization_id": Json(service.owner.organization_id),
        "display_name": Json(
          organizations
          .iter()
          .find_first(org => {
            org.organization_id == service.owner.organization_id
          })
          .map_or(service.owner.tenant_ref, org => org.display_name),
        ),
        "fixed_company": Json(service.reserves_company_node()),
      })
    }
  }
  json_reply(200, Json(rows))
}
