///|
test "terminal output redacts credential-shaped lines and bounds rows" {
  assert_eq(
    public_line("Authorization: Bearer never-print-this"),
    "{\"kind\":\"line\",\"text\":\"[redacted sensitive output]\"}",
  )
  let long = "x".repeat(5000)
  let encoded = public_line(long)
  assert_true(encoded.length() < 4200)
  assert_true(encoded.contains("…"))
}

///|
test "only the known harmless non-interactive bash bind warning is collapsed" {
  assert_true(
    ignorable_remote_shell_noise(
      "/home/operator/.bashrc: line 7: bind: warning: line editing not enabled",
    ),
  )
  assert_false(
    ignorable_remote_shell_noise(
      "/home/operator/.bashrc: line 7: command not found: kubectl",
    ),
  )
  assert_false(
    ignorable_remote_shell_noise("bind: warning: line editing not enabled"),
  )
}

///|
test "process arguments preserve values as separate argv entries" {
  let request : @install_contract.InstallRequest = {
    version: @install_contract.request_version,
    deployment_target: ManagementAndCompute,
    apply: false,
    confirmation: "",
    ssh_user: "operator",
    ssh_port: 32123,
    ssh_key_path: "/keys/id",
    known_hosts_path: "/keys/known_hosts",
    management_node: "management-01",
    management_host: "10.0.0.10",
    compute_nodes: [
      { node_name: "dgx-01", ssh_host: "10.0.0.21" },
      { node_name: "dgx-02", ssh_host: "10.0.0.22" },
      { node_name: "dgx-03", ssh_host: "10.0.0.23" },
      { node_name: "dgx-04", ssh_host: "10.0.0.24" },
    ],
    cluster_namespace: "lunanexa",
    kubeconfig_path: "/kube/config",
    rendered_directory: "/rendered",
    management_secret_manifest: "/secrets/management.yaml",
    secret_directory: "/secrets",
    cli_path: "/bin/lunanexa",
  }
  let arguments = process_arguments(request)
  assert_true(arguments.contains("--management-host"))
  assert_true(arguments.contains("--management-secret-manifest"))
  assert_true(arguments.contains("/secrets/management.yaml"))
  assert_true(arguments.contains("10.0.0.10"))
  assert_true(arguments.contains("32123"))
  assert_true(arguments.contains("management-and-compute"))
  assert_eq(arguments.filter(value => value == "--compute").length(), 4)
}
