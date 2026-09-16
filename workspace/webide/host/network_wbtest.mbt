///|
test "workspace gateway egress uses one namespace-and-role peer with one port" {
  let config = {
    ..host_config(),
    model_gateway_namespace: "trusted-gateway",
    model_gateway_port: 5883,
  }
  let host = WorkspaceHost::new(config)
  let grant = proxy_config(
    config.controller_origin,
    config.model_gateway_origin,
  ).grant()
  let resources = host.resources(@webide.workspace_id(grant), grant)
  guard resources[0].1
    is {
      "kind": "NetworkPolicy",
      "spec": {
        "policyTypes": Array(policy_types),
        "egress": Array(egress),
        "ingress": Array(ingress),
        ..
      },
      ..
    } else {
    fail("Network policy must precede runnable resources")
  }
  assert_eq(policy_types, ["Ingress", "Egress"])
  assert_eq(egress.length(), 3)
  assert_eq(ingress.length(), 1)
  json_inspect(egress[2], content={
    "to": [
      {
        "namespaceSelector": {
          "matchLabels": { "kubernetes.io/metadata.name": "trusted-gateway" },
        },
        "podSelector": {
          "matchLabels": { "lunanexa.io/model-gateway": "true" },
        },
      },
    ],
    "ports": [{ "protocol": "TCP", "port": 5883 }],
  })
  // Exact equality rejects accidental OR peers, empty selectors and extra ports.
  assert_false(resources[0].1.stringify().contains("ipBlock"))
  assert_false(resources[0].1.stringify().contains("0.0.0.0/0"))
}
