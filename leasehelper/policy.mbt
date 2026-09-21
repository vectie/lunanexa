///|
pub(all) struct CleanupEvidence {
  account_absent : Bool
  processes_absent : Bool
  containers_absent : Bool
  volumes_absent : Bool
  home_absent : Bool
  lease_state_absent : Bool
  access_material_absent : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn CleanupEvidence::verified(self : CleanupEvidence) -> Bool {
  self.account_absent &&
  self.processes_absent &&
  self.containers_absent &&
  self.volumes_absent &&
  self.home_absent &&
  self.lease_state_absent &&
  self.access_material_absent
}

///|
pub fn valid_host_root(root : String) -> Bool {
  root.length() >= 8 &&
  root.length() <= 512 &&
  root.has_prefix("/") &&
  root != "/" &&
  !root.has_suffix("/") &&
  !root.contains("//") &&
  !root.contains("/../") &&
  !root.has_suffix("/..") &&
  root.all(character => character.is_printable() && !character.is_whitespace())
}

///|
pub fn scoped_host_path(
  root : String,
  identifier : String,
  maximum_identifier_length? : Int = 128,
) -> String? {
  if valid_host_root(root) &&
    identifier != "." &&
    identifier != ".." &&
    @contracts.valid_identifier(
      identifier,
      maximum_length=maximum_identifier_length,
    ) {
    Some("\{root}/\{identifier}")
  } else {
    None
  }
}

///|
pub fn valid_runtime_object_id(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 128 &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '_' ||
    character == '-' ||
    character == '.'
  })
}

///|
pub fn valid_helper_request(
  action : String,
  lease_id : String,
  username : String,
  generation : Int64,
  expires_unix_ms : Int64,
  now_unix_ms : Int64,
) -> Bool {
  let known_action = action == "provision" ||
    action == "revoke" ||
    action == "sanitize" ||
    action == "quarantine"
  known_action &&
  @contracts.valid_identifier(lease_id) &&
  generation > 0L &&
  (action == "quarantine" || @nodelease.valid_unix_username(username)) &&
  (action != "provision" || expires_unix_ms > now_unix_ms)
}
