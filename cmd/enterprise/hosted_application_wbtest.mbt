///|
test "hosted applications keep the signed-in portal origin on both ingress ports" {
  for app in ["procurement", "bp"] {
    for origin in ["https://suanli.example", "https://suanli.example:8443"] {
      for catalog in ["https://suanli.example", "https://suanli.example:8443"] {
        let path = "/user/business/\{app}/connect?view=report#existing=1"
        assert_eq(
          hosted_application_uri(catalog + path, origin + "/user"),
          origin + path,
        )
      }
    }
  }
}

///|
test "hosted origin reuse does not rewrite external desktop or unrelated services" {
  for
    uri in [
      "https://external.example/user/business/bp/connect", "http://suanli.example/user/business/bp/connect",
      "https://suanli.example:5005/user/business/bp/connect", "https://suanli.example:8443/comfyui/connect",
      "moondesk://connect", "https://name:password@suanli.example:8443/user/business/bp/connect",
    ] {
    assert_eq(hosted_application_uri(uri, "https://suanli.example/user"), uri)
  }
}
