///|
/// Keep the transport's header key type at the HTTP boundary. In-process
/// adapters retain the provider-neutral string map used by the public API.
fn application_headers(headers : @http.Headers) -> Map[String, String] {
  Map(headers.iter().map(entry => (entry.0.to_string(), entry.1)).to_array())
}
