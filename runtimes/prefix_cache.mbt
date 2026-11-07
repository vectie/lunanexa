///|
fn OpenAiTextRuntime::isolate_prefix_cache(
  self : Self,
  request : @contracts.WorkloadEnvelope,
  upstream : Json,
) -> Unit {
  if self.prefix_cache_isolation && upstream is Object(fields) {
    let opted_in = request.data_policy.allow_cache ||
      request.payload is { "runtime_prefix_cache": true, .. }
    let scope = if opted_in {
      request.tenant_ref
    } else {
      request.tenant_ref + ":" + request.workload_id
    }
    fields["cache_salt"] = Json::string(
      @crypto.bytes_to_hex_string(
        @crypto.hmac(
          @crypto.SHA256::new(),
          @utf8.encode(self.credential_value),
          @utf8.encode("prefix-cache/v1:" + scope),
        ),
      ),
    )
  }
}

///|
fn cached_input_tokens(event : Json) -> Json {
  match event {
    {
      "response": {
        "usage": {
          "input_tokens_details": { "cached_tokens": Number(n, ..), .. },
          ..
        },
        ..
      },
      ..
    } if n >= 0.0 => Json(n)
    _ => Json::null()
  }
}
