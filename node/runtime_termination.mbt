///|
/// Domain-separated MAC for the entire termination report, including node,
/// send time, ordering and every immutable evidence field. It cannot be reused
/// as a heartbeat or assignment signature.
pub fn termination_report_signature(
  report : @contracts.RuntimeTerminationReport,
  secret : String,
) -> String {
  let unsigned = { ..report, signature: "", }
  let key = @utf8.encode(secret)
  let material = @utf8.encode(
    "lunanexa.runtime-termination-mac.v1|" +
    ToJson::to_json(unsigned).stringify(),
  )
  @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.exact_view(), material.exact_view()),
  )
}
