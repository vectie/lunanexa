///|
/// The GLM adapter is optional and site-owned. Its origin must be supplied by
/// deployment configuration, not compiled into the controller binary.
pub fn valid_origin(origin : String) -> Bool {
  if origin.trim().to_owned() != origin {
    return false
  }
  let authority = if origin.has_prefix("http://") {
    origin[7:].to_owned()
  } else if origin.has_prefix("https://") {
    origin[8:].to_owned()
  } else {
    return false
  }
  authority != "" &&
  !authority.contains("/") &&
  !authority.contains("?") &&
  !authority.contains("#") &&
  !authority.contains("@") &&
  !authority.contains("\\") &&
  !authority.contains(" ")
}
