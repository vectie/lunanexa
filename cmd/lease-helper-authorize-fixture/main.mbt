///| Test-only authorization producer for the destructive host simulation. This

///|
/// binary is not installed by any deployment manifest or release image.
fn argument_value(args : Array[String], name : String) -> String? {
  for index in 2..<(args.length() - 1) {
    if args[index] == name {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn int64_argument(args : Array[String], name : String) -> Int64? {
  Some(@string.parse_int64(argument_value(args, name).unwrap_or("0"))) catch {
    _ => None
  }
}

///|
fn action(args : Array[String]) -> @nodelease.LeaseAgentAction? {
  guard args.length() >= 2 &&
    argument_value(args, "--lease-id") is Some(lease_id) &&
    @contracts.valid_identifier(lease_id) &&
    argument_value(args, "--username") is Some(username) &&
    @nodelease.valid_unix_username(username) &&
    int64_argument(args, "--generation") is Some(generation) &&
    generation > 0L else {
    return None
  }
  match args[1] {
    "provision" => {
      guard argument_value(args, "--credential-ref") is Some(credential_ref) &&
        @nodelease.valid_access_credential_ref(credential_ref) &&
        int64_argument(args, "--expires-unix-ms") is Some(expires_unix_ms) else {
        return None
      }
      Some(
        ProvisionAccess(
          lease_id~,
          username~,
          credential_ref~,
          expires_unix_ms~,
          generation~,
        ),
      )
    }
    "revoke" => Some(RevokeAccess(lease_id~, username~, generation~))
    "sanitize" => Some(SanitizeLease(lease_id~, username~, generation~))
    "quarantine" => Some(QuarantineNode(lease_id~, username~, generation~))
    _ => None
  }
}

///|
fn main raise {
  guard @env.get_env_var("LUNANEXA_FIXTURE_HELPER_SECRET") is Some(secret) &&
    secret.length() >= 32 &&
    action(@env.args()) is Some(requested) else {
    raise Failure::Failure("helper authorization fixture input is invalid")
  }
  let now = @async.now()
  println(
    @nodelease.signed_helper_authorization(
      requested,
      now,
      now + 86400000L,
      secret,
    ),
  )
}
