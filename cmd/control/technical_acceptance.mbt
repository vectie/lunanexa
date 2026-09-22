///|
/// A missing deployment scope leaves technical waivers disabled. Decoding
/// errors never echo the supplied JSON; the API validates exact scope binding.
fn technical_acceptance_authorization(
  value : String?,
) -> @offline.TechnicalAcceptanceAuthorization? raise {
  guard value is Some(raw) else { return None }
  guard raw.length() > 0 && raw.length() <= 4096 else {
    fail("technical acceptance authorization exceeds its configuration bound")
  }
  let scope : @offline.TechnicalAcceptanceAuthorization = @json.from_json(
    @json.parse(raw),
  ) catch {
    _ => fail("invalid technical acceptance authorization configuration")
  }
  Some(scope)
}
