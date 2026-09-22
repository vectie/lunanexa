///|
/// The operator has to paste the identity provider's raw subject, but the
/// product only ever displays the derived `subject-…` reference. This is the
/// check that the console now shows the operator the reference their paste
/// will produce, using the same derivation the account store persists.
test "the provider subject field previews the reference the account store will persist" {
  let issuer = "https://106.39.18.146:5006/realms/lunanexa"
  let subject = "30101bc7-1f2e-4a5b-8c9d-0e1f2a3b4c5d"
  let html = render({
    ..default_state(),
    route: Users,
    access_package_draft: {
      identity_issuer: issuer,
      identity_subject: subject,
      display_name: "WebIDE developer",
      email: "developer@example.test",
      organization_id: "organization-1",
      tenant_ref: "tenant-1",
      lifetime_days: 30,
      identity_verified: true,
    },
  })
  let reference = @identity.subject_reference(issuer, subject)
  let account_id = @identity.account_identifier(issuer, subject)
  assert_true(html.contains(reference))
  assert_true(html.contains(account_id))
  assert_true(html.contains("access-provider-subject-help"))
  assert_true(html.contains("check it against the Subject column below"))
}

///|
test "an empty provider subject explains what to paste instead of deriving" {
  let html = render({ ..default_state(), route: Users, })
  assert_true(html.contains("Paste the provider"))
  assert_true(html.contains("not the derived reference"))
  assert_false(html.contains("Derives subject-"))
}

///|
/// The preview must hash the field exactly as submitted. A trailing space is a
/// realistic paste accident, and normalising it here would show a reference
/// that matches the account row while the control plane persisted a different
/// one -- the precise failure this preview exists to prevent.
test "a stray space changes the preview instead of being normalised away" {
  let issuer = "https://id.example"
  let clean = render({
    ..default_state(),
    route: Users,
    access_package_draft: {
      identity_issuer: issuer,
      identity_subject: "abc",
      display_name: "",
      email: "",
      organization_id: "",
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
  })
  let padded = render({
    ..default_state(),
    route: Users,
    access_package_draft: {
      identity_issuer: issuer,
      identity_subject: "abc ",
      display_name: "",
      email: "",
      organization_id: "",
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
  })
  assert_true(clean.contains(@identity.subject_reference(issuer, "abc")))
  assert_false(clean.contains(@identity.subject_reference(issuer, "abc ")))
  assert_true(padded.contains(@identity.subject_reference(issuer, "abc ")))
}

///|
test "the account-only form previews the same reference" {
  let issuer = "https://id.example"
  let subject = "abc"
  let html = render({
    ..default_state(),
    route: Users,
    account_invite: {
      account_id: "account-1",
      subject_ref: "subject-1",
      identity_issuer: issuer,
      identity_subject: subject,
      display_name: "Ari Chen",
      email: "ari@example.test",
      identity_receipt: "oidc-verified",
      roles: [EnterpriseUser],
    },
  })
  assert_true(html.contains(@identity.account_identifier(issuer, subject)))
  assert_true(html.contains("account-provider-subject-help"))
  assert_false(
    html.contains(
      "neither the provider subject nor its digest appears in account views",
    ),
  )
}
