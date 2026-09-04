///|
enum AccountPersistence {
  AccountFile(String)
  AccountPostgres(@database.PostgresDatabase)
}

///|
pub struct AccountStore {
  persistence : AccountPersistence
  issuer_secret : String
  mut accounts : Map[String, HumanAccount]
  mut sessions : Map[String, BrowserSession]
  mut invitations : Map[String, AccountInvitation]
  mut trials : Map[String, TrialEntitlement]
  mutex : @async.Mutex
}

///|
fn digest(value : String) -> String {
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))}"
}

///|
pub fn identity_subject_digest(issuer : String, subject : String) -> String {
  digest("lunanexa.external-identity.v1\n\{issuer}\n\{subject}")
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn valid_text(value : String, maximum : Int) -> Bool {
  value.trim() != "" &&
  value.length() <= maximum &&
  value.all(character => {
    character.is_printable() && character != '\n' && character != '\r'
  })
}

///|
fn valid_roles(roles : Array[AccountRole]) -> Bool {
  roles.length() > 0 &&
  roles.length() <= 3 &&
  roles.all(role => roles.count(role) == 1)
}

///|
pub fn validate_account(account : HumanAccount) -> Unit raise AccountError {
  if account.version != contract_version ||
    !@contracts.valid_identifier(account.account_id) ||
    !@contracts.valid_identifier(account.subject_ref) ||
    !valid_text(account.identity_issuer, 512) ||
    account.identity_subject_sha256.length() != 71 ||
    !account.identity_subject_sha256.has_prefix("sha256:") ||
    !@contracts.valid_identifier(account.identity_receipt, maximum_length=512) ||
    !valid_text(account.display_name, 128) ||
    !valid_text(account.email, 320) ||
    !valid_roles(account.roles) ||
    account.created_unix_ms <= 0L ||
    account.updated_unix_ms < account.created_unix_ms {
    raise InvalidInput("invalid human account")
  }
}

///|
fn validate_session(session : BrowserSession) -> Unit raise AccountError {
  if !@contracts.valid_identifier(session.session_id) ||
    !@contracts.valid_identifier(session.account_id) ||
    session.secret_sha256.length() != 71 ||
    !session.secret_sha256.has_prefix("sha256:") ||
    session.source_assertion_sha256.length() != 71 ||
    !session.source_assertion_sha256.has_prefix("sha256:") ||
    session.created_unix_ms <= 0L ||
    session.expires_unix_ms <= session.created_unix_ms ||
    session.expires_unix_ms - session.created_unix_ms > 43200000L ||
    session.last_used_unix_ms < session.created_unix_ms ||
    session.last_used_unix_ms > session.expires_unix_ms {
    raise InvalidInput("invalid browser session")
  }
}

///|
fn account_view(account : HumanAccount) -> AccountView {
  {
    account_id: account.account_id,
    subject_ref: account.subject_ref,
    identity_issuer: account.identity_issuer,
    display_name: account.display_name,
    email: account.email,
    identity_receipt: account.identity_receipt,
    roles: account.roles,
    state: account.state,
    created_unix_ms: account.created_unix_ms,
    updated_unix_ms: account.updated_unix_ms,
  }
}

///|
fn session_view(session : BrowserSession) -> BrowserSessionView {
  {
    session_id: session.session_id,
    account_id: session.account_id,
    created_unix_ms: session.created_unix_ms,
    expires_unix_ms: session.expires_unix_ms,
    last_used_unix_ms: session.last_used_unix_ms,
    revoked_unix_ms: session.revoked_unix_ms,
  }
}

///|
fn invitation_view(invitation : AccountInvitation) -> AccountInvitationView {
  {
    invitation_id: invitation.invitation_id,
    email: invitation.email,
    organization_id: invitation.organization_id,
    tenant_ref: invitation.tenant_ref,
    project_id: invitation.project_id,
    created_by: invitation.created_by,
    created_unix_ms: invitation.created_unix_ms,
    expires_unix_ms: invitation.expires_unix_ms,
    consumed_account_id: invitation.consumed_account_id,
    consumed_unix_ms: invitation.consumed_unix_ms,
  }
}

///|
fn sorted_accounts(values : Map[String, HumanAccount]) -> Array[HumanAccount] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.account_id)
  result
}

///|
fn sorted_sessions(
  values : Map[String, BrowserSession],
) -> Array[BrowserSession] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.session_id)
  result
}

///|
fn sorted_invitations(
  values : Map[String, AccountInvitation],
) -> Array[AccountInvitation] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.invitation_id)
  result
}

///|
fn sorted_trials(
  values : Map[String, TrialEntitlement],
) -> Array[TrialEntitlement] {
  let result = values.values().to_array()
  result.sort_by_key(value => value.trial_id)
  result
}

///|
let completed_session_retention_ms : Int64 = 2592000000L

///|
fn AccountStore::prune_completed_sessions_unlocked(
  self : AccountStore,
  now_unix_ms : Int64,
) -> Unit {
  let cutoff = now_unix_ms - completed_session_retention_ms
  let removable = self.sessions
    .values()
    .filter(session => {
      let completed = session.revoked_unix_ms.unwrap_or(session.expires_unix_ms)
      completed <= cutoff
    })
    .map(session => session.session_id)
  for session_id in removable {
    ignore(self.sessions.remove(session_id))
  }
}

///|
fn AccountStore::snapshot_unlocked(self : AccountStore) -> AccountSnapshot {
  {
    schema_version: snapshot_schema_version,
    accounts: sorted_accounts(self.accounts),
    sessions: sorted_sessions(self.sessions),
    invitations: Some(sorted_invitations(self.invitations)),
    trials: Some(sorted_trials(self.trials)),
  }
}

///|
async fn AccountStore::persist(self : AccountStore) -> Unit {
  let snapshot = self.snapshot_unlocked()
  match self.persistence {
    AccountFile(path) => {
      let temporary = "\{path}.next"
      @fs.write_file(
        temporary,
        snapshot.to_json().stringify(),
        create_mode=CreateOrTruncate,
        permission=0o600,
        sync=Full,
      )
      @fs.rename(temporary, path, replace=true)
    }
    AccountPostgres(database) =>
      database.save_opaque_snapshot(
        "accounts",
        snapshot_schema_version,
        snapshot.to_json().stringify(),
      )
  }
}

///|
fn AccountStore::restore(
  self : AccountStore,
  snapshot : AccountSnapshot,
) -> Unit raise AccountError {
  if snapshot.schema_version != snapshot_schema_version {
    raise InvalidSnapshot("unsupported account snapshot")
  }
  let subjects : Map[String, Unit] = Map([])
  let external_identities : Map[String, Unit] = Map([])
  for account in snapshot.accounts {
    validate_account(account)
    if self.accounts.contains(account.account_id) ||
      subjects.contains(account.subject_ref) ||
      external_identities.contains(
        "\{account.identity_issuer}|\{account.identity_subject_sha256}",
      ) {
      raise InvalidSnapshot("duplicate account identity")
    }
    self.accounts[account.account_id] = account
    subjects[account.subject_ref] = ()
    external_identities["\{account.identity_issuer}|\{account.identity_subject_sha256}"] = ()
  }
  let assertions : Map[String, Unit] = Map([])
  for session in snapshot.sessions {
    validate_session(session)
    if self.sessions.contains(session.session_id) ||
      !self.accounts.contains(session.account_id) ||
      assertions.contains(session.source_assertion_sha256) {
      raise InvalidSnapshot("invalid account session")
    }
    self.sessions[session.session_id] = session
    assertions[session.source_assertion_sha256] = ()
  }
  for invitation in snapshot.invitations.unwrap_or([]) {
    if !@contracts.valid_identifier(invitation.invitation_id) ||
      !valid_text(invitation.email, 320) ||
      !@contracts.valid_identifier(invitation.organization_id) ||
      !@contracts.valid_identifier(invitation.tenant_ref) ||
      !@contracts.valid_identifier(invitation.project_id) ||
      !@contracts.valid_identifier(invitation.created_by) ||
      invitation.secret_sha256.length() != 71 ||
      !invitation.secret_sha256.has_prefix("sha256:") ||
      invitation.created_unix_ms <= 0L ||
      invitation.expires_unix_ms <= invitation.created_unix_ms ||
      (invitation.consumed_account_id is Some(_)) !=
      (invitation.consumed_unix_ms is Some(_)) ||
      invitation.consumed_account_id.map_or(false, account_id => {
        !self.accounts.contains(account_id)
      }) ||
      self.invitations.contains(invitation.invitation_id) {
      raise InvalidSnapshot("invalid account invitation")
    }
    self.invitations[invitation.invitation_id] = invitation
  }
  for trial in snapshot.trials.unwrap_or([]) {
    if !@contracts.valid_identifier(trial.trial_id) ||
      !self.accounts.contains(trial.account_id) ||
      !@contracts.valid_identifier(trial.organization_id) ||
      !@contracts.valid_identifier(trial.tenant_ref) ||
      !@contracts.valid_identifier(trial.project_id) ||
      trial.allowed_models.length() == 0 ||
      trial.allowed_models.length() > 16 ||
      trial.allowed_models.any(model => !@contracts.valid_identifier(model)) ||
      trial.allowed_models.any(model => trial.allowed_models.count(model) != 1) ||
      trial.maximum_requests <= 0L ||
      trial.maximum_requests > 10000L ||
      trial.starts_unix_ms <= 0L ||
      trial.expires_unix_ms <= trial.starts_unix_ms ||
      trial.expires_unix_ms - trial.starts_unix_ms > 2592000000L ||
      trial.api_key_id.map_or(false, key_id => {
        !@contracts.valid_identifier(key_id)
      }) ||
      trial.revoked_unix_ms.map_or(false, revoked => {
        revoked < trial.starts_unix_ms
      }) ||
      self.trials.contains(trial.trial_id) ||
      self.trials.values().any(value => value.account_id == trial.account_id) {
      raise InvalidSnapshot("invalid trial entitlement")
    }
    self.trials[trial.trial_id] = trial
  }
}

///|
pub async fn AccountStore::open(
  path : String,
  issuer_secret : String,
) -> AccountStore {
  if path.trim() == "" ||
    issuer_secret.length() < 32 ||
    issuer_secret.length() > 4096 {
    raise InvalidInput("account store configuration is invalid")
  }
  let store : AccountStore = {
    persistence: AccountFile(path),
    issuer_secret,
    accounts: Map([]),
    sessions: Map([]),
    invitations: Map([]),
    trials: Map([]),
    mutex: Mutex(),
  }
  if @fs.exists(path) {
    let snapshot : AccountSnapshot = @json.from_json(
      @json.parse(@fs.read_file(path).text()),
    ) catch {
      error => raise InvalidSnapshot("\{Repr(error)}")
    }
    store.restore(snapshot)
  } else {
    store.persist()
  }
  store
}

///|
pub async fn AccountStore::open_postgres(
  database : @database.PostgresDatabase,
  issuer_secret : String,
) -> AccountStore {
  if issuer_secret.length() < 32 || issuer_secret.length() > 4096 {
    raise InvalidInput("account store configuration is invalid")
  }
  let store : AccountStore = {
    persistence: AccountPostgres(database),
    issuer_secret,
    accounts: Map([]),
    sessions: Map([]),
    invitations: Map([]),
    trials: Map([]),
    mutex: Mutex(),
  }
  match database.load_snapshot("accounts", snapshot_schema_version) {
    Some(payload) => {
      let snapshot : AccountSnapshot = @json.from_json(@json.parse(payload)) catch {
        error => raise InvalidSnapshot("\{Repr(error)}")
      }
      store.restore(snapshot)
    }
    None => store.persist()
  }
  store
}

///|
pub async fn AccountStore::snapshot(self : AccountStore) -> AccountSnapshot {
  self.mutex.acquire()
  let result = self.snapshot_unlocked()
  self.mutex.release()
  result
}

///|
/// Creates or resumes the single bounded free trial associated with an
/// account. The deterministic intent makes registration retries safe.
pub async fn AccountStore::ensure_trial(
  self : AccountStore,
  intent : TrialEntitlementIntent,
  now_unix_ms : Int64,
) -> TrialEntitlement {
  if !@contracts.valid_identifier(intent.trial_id) ||
    !@contracts.valid_identifier(intent.account_id) ||
    !@contracts.valid_identifier(intent.organization_id) ||
    !@contracts.valid_identifier(intent.tenant_ref) ||
    !@contracts.valid_identifier(intent.project_id) ||
    intent.allowed_models.length() == 0 ||
    intent.allowed_models.length() > 16 ||
    intent.allowed_models.any(model => !@contracts.valid_identifier(model)) ||
    intent.allowed_models.any(model => intent.allowed_models.count(model) != 1) ||
    intent.maximum_requests <= 0L ||
    intent.maximum_requests > 10000L ||
    now_unix_ms <= 0L ||
    intent.expires_unix_ms <= now_unix_ms ||
    intent.expires_unix_ms - now_unix_ms > 2592000000L {
    raise InvalidInput("invalid trial entitlement")
  }
  self.mutex.acquire()
  let previous = self.trials.copy()
  try {
    guard self.accounts.get(intent.account_id) is Some(account) &&
      account.state == Active &&
      role_allows(account.roles, EnterpriseUser) else {
      raise Unauthorized
    }
    match self.trials.get(intent.trial_id) {
      Some(existing) => {
        if existing.account_id != intent.account_id ||
          existing.organization_id != intent.organization_id ||
          existing.tenant_ref != intent.tenant_ref ||
          existing.project_id != intent.project_id ||
          existing.allowed_models != intent.allowed_models ||
          existing.maximum_requests != intent.maximum_requests {
          raise AlreadyExists(intent.trial_id)
        }
        self.mutex.release()
        return existing
      }
      None => ()
    }
    if self.trials.values().any(value => value.account_id == intent.account_id) {
      raise AlreadyExists(intent.account_id)
    }
    let trial : TrialEntitlement = {
      trial_id: intent.trial_id,
      account_id: intent.account_id,
      organization_id: intent.organization_id,
      tenant_ref: intent.tenant_ref,
      project_id: intent.project_id,
      allowed_models: intent.allowed_models,
      maximum_requests: intent.maximum_requests,
      starts_unix_ms: now_unix_ms,
      expires_unix_ms: intent.expires_unix_ms,
      api_key_id: None,
      revoked_unix_ms: None,
    }
    self.trials[intent.trial_id] = trial
    self.persist()
    self.mutex.release()
    trial
  } catch {
    error => {
      self.trials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::trial_for_account(
  self : AccountStore,
  account_id : String,
) -> TrialEntitlement? {
  self.mutex.acquire()
  let value = self.trials
    .values()
    .find_first(trial => trial.account_id == account_id)
  self.mutex.release()
  value
}

///|
pub async fn AccountStore::active_trial_for_subject(
  self : AccountStore,
  subject_ref : String,
  now_unix_ms : Int64,
) -> TrialEntitlement? {
  self.mutex.acquire()
  let account_id = self.accounts
    .values()
    .find_first(account => {
      account.subject_ref == subject_ref && account.state == Active
    })
    .map(account => account.account_id)
  let value = match account_id {
    Some(id) =>
      self.trials
      .values()
      .find_first(trial => {
        trial.account_id == id &&
        trial.starts_unix_ms <= now_unix_ms &&
        trial.expires_unix_ms > now_unix_ms &&
        trial.revoked_unix_ms is None
      })
    None => None
  }
  self.mutex.release()
  value
}

///|
pub async fn AccountStore::bind_trial_api_key(
  self : AccountStore,
  trial_id : String,
  key_id : String,
  now_unix_ms : Int64,
) -> TrialEntitlement {
  if !@contracts.valid_identifier(trial_id) ||
    !@contracts.valid_identifier(key_id) {
    raise InvalidInput("invalid trial API key binding")
  }
  self.mutex.acquire()
  let previous = self.trials.copy()
  try {
    guard self.trials.get(trial_id) is Some(trial) &&
      trial.expires_unix_ms > now_unix_ms &&
      trial.revoked_unix_ms is None else {
      raise Unauthorized
    }
    match trial.api_key_id {
      Some(existing) if existing != key_id => raise AlreadyExists(trial_id)
      Some(_) => {
        self.mutex.release()
        return trial
      }
      None => ()
    }
    let updated = { ..trial, api_key_id: Some(key_id) }
    self.trials[trial_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.trials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::revoke_trial_for_account(
  self : AccountStore,
  account_id : String,
  now_unix_ms : Int64,
) -> TrialEntitlement {
  self.mutex.acquire()
  let previous = self.trials.copy()
  try {
    guard self.trials
      .values()
      .find_first(trial => trial.account_id == account_id)
      is Some(trial) else {
      raise NotFound(account_id)
    }
    let updated = match trial.revoked_unix_ms {
      Some(_) => trial
      None => { ..trial, revoked_unix_ms: Some(now_unix_ms) }
    }
    self.trials[trial.trial_id] = updated
    self.persist()
    self.mutex.release()
    updated
  } catch {
    error => {
      self.trials = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
fn AccountStore::invitation_secret(
  self : AccountStore,
  intent : AccountInvitationIntent,
  now_unix_ms : Int64,
) -> String {
  let material = "lunanexa.account-invitation.v1|\{intent.invitation_id}|\{intent.email}|\{intent.organization_id}|\{intent.tenant_ref}|\{intent.project_id}|\{intent.expires_unix_ms}|\{now_unix_ms}"
  "lnxi_\{@crypto.bytes_to_hex_string(@crypto.hmac(@crypto.SHA256::new(), @utf8.encode(self.issuer_secret).view(), @utf8.encode(material).view()))}"
}

///|
pub async fn AccountStore::issue_invitation(
  self : AccountStore,
  intent : AccountInvitationIntent,
  now_unix_ms : Int64,
) -> IssuedAccountInvitation {
  if !@contracts.valid_identifier(intent.invitation_id) ||
    !valid_text(intent.email, 320) ||
    !@contracts.valid_identifier(intent.organization_id) ||
    !@contracts.valid_identifier(intent.tenant_ref) ||
    !@contracts.valid_identifier(intent.project_id) ||
    !@contracts.valid_identifier(intent.created_by) ||
    now_unix_ms <= 0L ||
    intent.expires_unix_ms <= now_unix_ms ||
    intent.expires_unix_ms - now_unix_ms > 2592000000L {
    raise InvalidInput("invalid account invitation")
  }
  let secret = self.invitation_secret(intent, now_unix_ms)
  self.mutex.acquire()
  let previous = self.invitations.copy()
  try {
    if self.invitations.contains(intent.invitation_id) ||
      self.invitations
      .values()
      .any(invitation => {
        invitation.email.to_lower() == intent.email.to_lower() &&
        invitation.consumed_unix_ms is None &&
        invitation.expires_unix_ms > now_unix_ms
      }) {
      raise AlreadyExists(intent.invitation_id)
    }
    let invitation : AccountInvitation = {
      invitation_id: intent.invitation_id,
      secret_sha256: digest(secret),
      email: intent.email,
      organization_id: intent.organization_id,
      tenant_ref: intent.tenant_ref,
      project_id: intent.project_id,
      created_by: intent.created_by,
      created_unix_ms: now_unix_ms,
      expires_unix_ms: intent.expires_unix_ms,
      consumed_account_id: None,
      consumed_unix_ms: None,
    }
    self.invitations[intent.invitation_id] = invitation
    self.persist()
    self.mutex.release()
    { invitation: invitation_view(invitation), secret }
  } catch {
    error => {
      self.invitations = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::invitation_views(
  self : AccountStore,
) -> Array[AccountInvitationView] {
  self.mutex.acquire()
  let values = sorted_invitations(self.invitations).map(invitation_view)
  self.mutex.release()
  values
}

///|
pub async fn AccountStore::register_with_invitation(
  self : AccountStore,
  invitation_secret : String,
  identity_issuer : String,
  identity_subject : String,
  identity_email : String,
  source_assertion : String,
  display_name : String,
  lifetime_ms : Int64,
  now_unix_ms : Int64,
) -> RegisteredAccount {
  if invitation_secret.length() != 69 ||
    !invitation_secret.has_prefix("lnxi_") ||
    !valid_text(identity_issuer, 512) ||
    identity_subject == "" ||
    identity_subject.length() > 1024 ||
    !valid_text(identity_email, 320) ||
    !valid_text(display_name, 128) ||
    source_assertion == "" ||
    source_assertion.length() > 4096 ||
    lifetime_ms < 30000L ||
    lifetime_ms > 43200000L {
    raise InvalidInput("invalid invited registration")
  }
  let secret_digest = digest(invitation_secret)
  let external_digest = identity_subject_digest(
    identity_issuer, identity_subject,
  )
  let fingerprint = external_digest[7:31].to_owned()
  let account_id = "account-\{fingerprint}"
  let subject_ref = "subject-\{fingerprint}"
  self.mutex.acquire()
  let previous_accounts = self.accounts.copy()
  let previous_invitations = self.invitations.copy()
  let result = try {
    let mut matched : AccountInvitation? = None
    for invitation in self.invitations.values() {
      if constant_time_equal(invitation.secret_sha256, secret_digest) {
        matched = Some(invitation)
      }
    }
    guard matched is Some(invitation) else { raise Unauthorized }
    if invitation.email.to_lower() != identity_email.to_lower() {
      raise Unauthorized
    }
    if invitation.expires_unix_ms <= now_unix_ms {
      raise Unauthorized
    }
    match invitation.consumed_account_id {
      Some(consumed_id) => {
        guard consumed_id == account_id &&
          self.accounts.get(consumed_id) is Some(existing) &&
          existing.identity_issuer == identity_issuer &&
          existing.identity_subject_sha256 == external_digest &&
          existing.state == Active else {
          raise Unauthorized
        }
      }
      None => {
        match self.accounts.get(account_id) {
          Some(existing) =>
            if existing.identity_issuer != identity_issuer ||
              existing.identity_subject_sha256 != external_digest ||
              existing.email.to_lower() != identity_email.to_lower() ||
              existing.state != Active ||
              !role_allows(existing.roles, EnterpriseUser) {
              raise AlreadyExists(account_id)
            }
          None => {
            if self.accounts
              .values()
              .any(account => {
                account.identity_issuer == identity_issuer &&
                account.identity_subject_sha256 == external_digest
              }) {
              raise AlreadyExists(account_id)
            }
            let account : HumanAccount = {
              version: contract_version,
              account_id,
              subject_ref,
              identity_issuer,
              identity_subject_sha256: external_digest,
              display_name,
              email: invitation.email,
              identity_receipt: "invitation:\{invitation.invitation_id}",
              roles: [EnterpriseUser],
              state: Active,
              created_unix_ms: now_unix_ms,
              updated_unix_ms: now_unix_ms,
            }
            self.accounts[account_id] = account
          }
        }
        self.invitations[invitation.invitation_id] = {
          ..invitation,
          consumed_account_id: Some(account_id),
          consumed_unix_ms: Some(now_unix_ms),
        }
      }
    }
    self.persist()
    let account = match self.accounts.get(account_id) {
      Some(value) => account_view(value)
      None => raise Unauthorized
    }
    let consumed = match self.invitations.get(invitation.invitation_id) {
      Some(value) => invitation_view(value)
      None => raise Unauthorized
    }
    self.mutex.release()
    (account, consumed)
  } catch {
    error => {
      self.accounts = previous_accounts
      self.invitations = previous_invitations
      self.mutex.release()
      raise error
    }
  }
  let session = self.issue_session(
    identity_issuer, identity_subject, source_assertion, lifetime_ms, now_unix_ms,
  )
  { account: result.0, invitation: result.1, session }
}

///|
/// Creates only a human account and browser session from a gateway-verified
/// identity. It deliberately creates no tenant membership, API key, contract,
/// workspace lease, or machine authority.
pub async fn AccountStore::register_open(
  self : AccountStore,
  identity_issuer : String,
  identity_subject : String,
  source_assertion : String,
  display_name : String,
  email : String,
  lifetime_ms : Int64,
  now_unix_ms : Int64,
) -> OpenRegisteredAccount {
  if !valid_text(identity_issuer, 512) ||
    identity_subject == "" ||
    identity_subject.length() > 1024 ||
    !valid_text(display_name, 128) ||
    !valid_text(email, 320) ||
    source_assertion == "" ||
    source_assertion.length() > 4096 ||
    lifetime_ms < 30000L ||
    lifetime_ms > 43200000L {
    raise InvalidInput("invalid open registration")
  }
  let external_digest = identity_subject_digest(
    identity_issuer, identity_subject,
  )
  let fingerprint = external_digest[7:31].to_owned()
  let account_id = "account-\{fingerprint}"
  let account = match
    self.views().iter().find_first(value => value.account_id == account_id) {
    Some(value) => {
      if value.identity_issuer != identity_issuer ||
        value.email.to_lower() != email.to_lower() ||
        value.state != Active ||
        !role_allows(value.roles, EnterpriseUser) {
        raise AlreadyExists(account_id)
      }
      value
    }
    None =>
      self.create({
        version: contract_version,
        account_id,
        subject_ref: "subject-\{fingerprint}",
        identity_issuer,
        identity_subject_sha256: external_digest,
        display_name,
        email,
        identity_receipt: "oidc-registration:\{fingerprint}",
        roles: [EnterpriseUser],
        state: Active,
        created_unix_ms: now_unix_ms,
        updated_unix_ms: now_unix_ms,
      })
  }
  let session = self.issue_session(
    identity_issuer, identity_subject, source_assertion, lifetime_ms, now_unix_ms,
  )
  { account, session }
}

///|
pub async fn AccountStore::create(
  self : AccountStore,
  account : HumanAccount,
) -> AccountView {
  validate_account(account)
  if account.state != Invited && account.state != Active {
    raise InvalidInput("new account must be invited or active")
  }
  self.mutex.acquire()
  let previous = self.accounts.copy()
  try {
    if self.accounts.contains(account.account_id) ||
      self.accounts
      .values()
      .any(value => {
        value.subject_ref == account.subject_ref ||
        (
          value.identity_issuer == account.identity_issuer &&
          value.identity_subject_sha256 == account.identity_subject_sha256
        )
      }) {
      raise AlreadyExists(account.account_id)
    }
    self.accounts[account.account_id] = account
    self.persist()
    self.mutex.release()
    account_view(account)
  } catch {
    error => {
      self.accounts = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
fn transition_allowed(from : AccountState, to : AccountState) -> Bool {
  match (from, to) {
    (Invited, Active | Suspended | Revoked) => true
    (Active, Suspended | Revoked) => true
    (Suspended, Active | Revoked) => true
    _ => false
  }
}

///|
pub async fn AccountStore::set_state(
  self : AccountStore,
  account_id : String,
  state : AccountState,
  now_unix_ms : Int64,
) -> AccountView {
  self.mutex.acquire()
  let previous_accounts = self.accounts.copy()
  let previous_sessions = self.sessions.copy()
  try {
    guard self.accounts.get(account_id) is Some(current) else {
      raise NotFound(account_id)
    }
    if !transition_allowed(current.state, state) ||
      now_unix_ms < current.updated_unix_ms {
      raise InvalidTransition(account_id)
    }
    let updated = { ..current, state, updated_unix_ms: now_unix_ms }
    self.accounts[account_id] = updated
    if state == Suspended || state == Revoked {
      for session_id, session in self.sessions {
        if session.account_id == account_id && session.revoked_unix_ms is None {
          self.sessions[session_id] = {
            ..session,
            revoked_unix_ms: Some(now_unix_ms),
          }
        }
      }
    }
    self.persist()
    self.mutex.release()
    account_view(updated)
  } catch {
    error => {
      self.accounts = previous_accounts
      self.sessions = previous_sessions
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::set_roles(
  self : AccountStore,
  account_id : String,
  roles : Array[AccountRole],
  now_unix_ms : Int64,
) -> AccountView {
  if !valid_roles(roles) {
    raise InvalidInput("invalid account roles")
  }
  self.mutex.acquire()
  let previous_accounts = self.accounts.copy()
  let previous_sessions = self.sessions.copy()
  try {
    guard self.accounts.get(account_id) is Some(current) else {
      raise NotFound(account_id)
    }
    if current.state == Revoked || now_unix_ms < current.updated_unix_ms {
      raise InvalidTransition(account_id)
    }
    let updated = { ..current, roles, updated_unix_ms: now_unix_ms }
    self.accounts[account_id] = updated
    // Role removal must take effect immediately for already issued sessions.
    for session_id, session in self.sessions {
      if session.account_id == account_id && session.revoked_unix_ms is None {
        self.sessions[session_id] = {
          ..session,
          revoked_unix_ms: Some(now_unix_ms),
        }
      }
    }
    self.persist()
    self.mutex.release()
    account_view(updated)
  } catch {
    error => {
      self.accounts = previous_accounts
      self.sessions = previous_sessions
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::views(self : AccountStore) -> Array[AccountView] {
  self.snapshot().accounts.map(account_view)
}

///|
fn AccountStore::session_material(
  self : AccountStore,
  account_id : String,
  now_unix_ms : Int64,
  ordinal : Int,
) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(self.issuer_secret).view(),
      @utf8.encode(
        "lunanexa.browser-session.v1|\{account_id}|\{now_unix_ms}|\{ordinal}",
      ).view(),
    ),
  )
}

///|
pub async fn AccountStore::issue_session(
  self : AccountStore,
  identity_issuer : String,
  identity_subject : String,
  source_assertion : String,
  lifetime_ms : Int64,
  now_unix_ms : Int64,
) -> IssuedBrowserSession {
  if !valid_text(identity_issuer, 512) ||
    identity_subject == "" ||
    identity_subject.length() > 1024 ||
    source_assertion == "" ||
    source_assertion.length() > 4096 ||
    lifetime_ms < 30000L ||
    lifetime_ms > 43200000L {
    raise InvalidInput("invalid browser session intent")
  }
  let assertion_digest = digest(source_assertion)
  let external_digest = identity_subject_digest(
    identity_issuer, identity_subject,
  )
  self.mutex.acquire()
  let previous = self.sessions.copy()
  try {
    self.prune_completed_sessions_unlocked(now_unix_ms)
    guard self.accounts
      .values()
      .find_first(value => {
        value.identity_issuer == identity_issuer &&
        value.identity_subject_sha256 == external_digest
      })
      is Some(account) &&
      account.state == Active else {
      raise Unauthorized
    }
    if self.sessions
      .values()
      .any(value => value.source_assertion_sha256 == assertion_digest) {
      raise AssertionReplayed
    }
    let active_session_count = self.sessions
      .values()
      .filter(session => {
        session.account_id == account.account_id &&
        session.revoked_unix_ms is None &&
        session.expires_unix_ms > now_unix_ms
      })
      .count()
    if active_session_count >= 8 {
      raise InvalidInput("account active-session limit is reached")
    }
    let ordinal = self.sessions.length()
    let material = self.session_material(
      account.account_id,
      now_unix_ms,
      ordinal,
    )
    let session_id = "session-\{material[:32]}"
    let secret = "lnxs_\{material}"
    if self.sessions.contains(session_id) {
      raise AlreadyExists(session_id)
    }
    let session : BrowserSession = {
      session_id,
      account_id: account.account_id,
      secret_sha256: digest(secret),
      source_assertion_sha256: assertion_digest,
      created_unix_ms: now_unix_ms,
      expires_unix_ms: now_unix_ms + lifetime_ms,
      last_used_unix_ms: now_unix_ms,
      revoked_unix_ms: None,
    }
    self.sessions[session_id] = session
    self.persist()
    self.mutex.release()
    { session: session_view(session), secret }
  } catch {
    error => {
      self.sessions = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::authorize(
  self : AccountStore,
  secret : String,
  now_unix_ms : Int64,
  required_role? : AccountRole,
) -> AccountAuthorization {
  if secret.length() != 69 || !secret.has_prefix("lnxs_") {
    raise Unauthorized
  }
  let secret_digest = digest(secret)
  self.mutex.acquire()
  let previous = self.sessions.copy()
  try {
    guard self.sessions
      .values()
      .find_first(value => {
        constant_time_equal(value.secret_sha256, secret_digest)
      })
      is Some(session) else {
      raise Unauthorized
    }
    guard self.accounts.get(session.account_id) is Some(account) else {
      raise Unauthorized
    }
    if account.state != Active ||
      session.revoked_unix_ms is Some(_) ||
      now_unix_ms < session.created_unix_ms ||
      session.expires_unix_ms <= now_unix_ms ||
      required_role
      .map(role => !role_allows(account.roles, role))
      .unwrap_or(false) {
      raise Unauthorized
    }
    let touched = { ..session, last_used_unix_ms: now_unix_ms }
    self.sessions[session.session_id] = touched
    self.persist()
    self.mutex.release()
    { session_id: session.session_id, account: account_view(account) }
  } catch {
    error => {
      self.sessions = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::sessions_for_account(
  self : AccountStore,
  account_id : String,
) -> Array[BrowserSessionView] {
  self.snapshot().sessions
  .filter(value => value.account_id == account_id)
  .map(session_view)
}

///|
pub async fn AccountStore::revoke_session(
  self : AccountStore,
  session_id : String,
  account_id : String,
  now_unix_ms : Int64,
) -> BrowserSessionView {
  self.mutex.acquire()
  let previous = self.sessions.copy()
  try {
    guard self.sessions.get(session_id) is Some(current) &&
      current.account_id == account_id else {
      raise NotFound(session_id)
    }
    let revoked = if current.revoked_unix_ms is Some(_) {
      current
    } else {
      { ..current, revoked_unix_ms: Some(now_unix_ms) }
    }
    self.sessions[session_id] = revoked
    self.persist()
    self.mutex.release()
    session_view(revoked)
  } catch {
    error => {
      self.sessions = previous
      self.mutex.release()
      raise error
    }
  }
}

///|
pub async fn AccountStore::revoke_all_sessions(
  self : AccountStore,
  account_id : String,
  now_unix_ms : Int64,
) -> Int {
  self.mutex.acquire()
  let previous = self.sessions.copy()
  try {
    if !self.accounts.contains(account_id) {
      raise NotFound(account_id)
    }
    let mut count = 0
    for session_id, session in self.sessions {
      if session.account_id == account_id && session.revoked_unix_ms is None {
        self.sessions[session_id] = {
          ..session,
          revoked_unix_ms: Some(now_unix_ms),
        }
        count += 1
      }
    }
    self.persist()
    self.mutex.release()
    count
  } catch {
    error => {
      self.sessions = previous
      self.mutex.release()
      raise error
    }
  }
}
