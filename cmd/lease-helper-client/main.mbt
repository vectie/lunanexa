///|
fn argument_value(args : Array[String], name : String) -> String? {
  for index in 2..<(args.length() - 1) {
    if args[index] == name {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn generation(args : Array[String]) -> Int64? {
  Some(@string.parse_int64(argument_value(args, "--generation").unwrap_or("0"))) catch {
    _ => None
  }
}

///|
fn int64_argument(args : Array[String], name : String) -> Int64? {
  Some(@string.parse_int64(argument_value(args, name).unwrap_or("0"))) catch {
    _ => None
  }
}

///|
fn expected_action(args : Array[String]) -> @nodelease.LeaseAgentAction? {
  guard args.length() >= 2 &&
    argument_value(args, "--lease-id") is Some(lease_id) &&
    @contracts.valid_identifier(lease_id) &&
    generation(args) is Some(generation) &&
    generation > 0L else {
    return None
  }
  let username = argument_value(args, "--username").unwrap_or("")
  match args[1] {
    "provision" => {
      guard @nodelease.valid_unix_username(username) &&
        argument_value(args, "--credential-ref") is Some(credential_ref) &&
        @nodelease.valid_access_credential_ref(credential_ref) &&
        int64_argument(args, "--expires-unix-ms") is Some(expires_unix_ms) &&
        expires_unix_ms > @async.now() else {
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
    "revoke" if @nodelease.valid_unix_username(username) =>
      Some(RevokeAccess(lease_id~, username~, generation~))
    "sanitize" if @nodelease.valid_unix_username(username) =>
      Some(SanitizeLease(lease_id~, username~, generation~))
    "quarantine" => Some(QuarantineNode(lease_id~, generation~))
    _ => None
  }
}

///|
async fn main {
  let args = @env.args()
  guard expected_action(args) is Some(action) else {
    raise Failure::Failure("lease helper client rejected unsafe arguments")
  }
  let helper_args = args[1:].to_owned()
  let (status, stdout) = @process.collect_stdout(
    "/usr/bin/sudo",
    ["--non-interactive", "/usr/libexec/lunanexa-lease-helper", ..helper_args],
    extra_env={
      "PATH": "/usr/sbin:/usr/bin:/sbin:/bin",
      "HOME": "/var/lib/lunanexa",
      "LANG": "C",
      "LC_ALL": "C",
    },
    inherit_env=false,
  )
  let receipt = stdout.text().trim().to_owned()
  if status != 0 || !@nodelease.valid_helper_receipt(action, receipt) {
    raise Failure::Failure("privileged lease helper failed closed")
  }
  println(receipt)
}
