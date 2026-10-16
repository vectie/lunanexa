///|
// Private-company administrators use personal workspace authority for the
// company pool. The sponsoring lease continues to govern its physical term.
async fn ApiService::private_company_reservation_authorized(
  self : ApiService,
  reservation : @scheduler.NodeReservation,
  subject : String,
  now : Int64,
) -> Bool {
  guard self.private_cloud_workspace_access &&
    reservation.state == Reserved &&
    reservation.request.starts_unix_ms <= now &&
    reservation.request.expires_unix_ms > now &&
    self.portal_store is Some(portal) &&
    self.workspace_directory is Some(directory) &&
    portal.snapshot().memberships.any(membership => {
      membership.active &&
      membership.subject_ref == subject &&
      membership.tenant_ref == reservation.request.tenant_ref &&
      membership.organization_id == reservation.request.organization_id &&
      membership.roles.contains(OrganizationAdministrator) &&
      @portal.role_allows(membership.roles, Developer)
    }) else {
    return false
  }
  guard directory.snapshot(now).leases
    .iter()
    .find_first(lease => {
      lease.lease_id == reservation.request.lease_id &&
      lease.tenant_ref == reservation.request.tenant_ref
    })
    is Some(sponsor) else {
    return false
  }
  try {
    ignore(
      directory.authorize_subject_for_tenant_lease(
        sponsor.subject_ref,
        reservation.request.tenant_ref,
        reservation.request.lease_id,
        Developer,
        now,
        grant_id=reservation.request.authority_ref,
      ),
    )
    ignore(
      directory.authorize_subject_for_tenant(
        subject,
        reservation.request.tenant_ref,
        Developer,
        now,
      ),
    )
    true
  } catch {
    _ => false
  }
}

///|
async fn ApiService::private_company_delivery_authorized(
  self : ApiService,
  reservation : @scheduler.NodeReservation,
  lease_id : String,
  grant_id : String,
  now : Int64,
) -> Bool {
  guard self.workspace_directory is Some(directory) &&
    directory.snapshot(now).leases
    .iter()
    .find_first(lease => {
      lease.lease_id == lease_id &&
      lease.tenant_ref == reservation.request.tenant_ref
    })
    is Some(personal) &&
    self.private_company_reservation_authorized(
      reservation,
      personal.subject_ref,
      now,
    ) else {
    return false
  }
  try {
    ignore(
      directory.authorize_subject_for_tenant_lease(
        personal.subject_ref,
        reservation.request.tenant_ref,
        lease_id,
        Developer,
        now,
        grant_id~,
      ),
    )
    true
  } catch {
    _ => false
  }
}
