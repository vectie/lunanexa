///|
fn valid_request(apply? : Bool = false) -> @installer.InstallRequest {
  {
    version: @installer.request_version,
    apply,
    confirmation: if apply {
      @installer.apply_confirmation
    } else {
      ""
    },
    ssh_user: "cluster-admin",
    ssh_key_path: "/Users/operator/.ssh/lunanexa",
    known_hosts_path: "/Users/operator/.ssh/known_hosts",
    management_node: "management-01",
    management_host: "10.0.0.10",
    compute_nodes: [
      { node_name: "dgx-spark-01", ssh_host: "10.0.0.21" },
      { node_name: "dgx-spark-02", ssh_host: "10.0.0.22" },
      { node_name: "dgx-spark-03", ssh_host: "10.0.0.23" },
      { node_name: "dgx-spark-04", ssh_host: "10.0.0.24" },
    ],
    cluster_namespace: "lunanexa",
    kubeconfig_path: "/Users/operator/.kube/config",
    rendered_directory: "/srv/lunanexa/rendered",
    secret_directory: "/srv/lunanexa/secrets",
    cli_path: "/usr/local/bin/lunanexa",
  }
}

///|
test "valid dry-run and confirmed apply requests" {
  @installer.validate_request(valid_request())
  @installer.validate_request(valid_request(apply=true))
}

///|
test "apply fails closed without exact confirmation" {
  try
    @installer.validate_request({
      ..valid_request(apply=true),
      confirmation: "deploy",
    })
  catch {
    InvalidField(field) => inspect(field, content="confirmation")
  } noraise {
    _ => fail("expected confirmation rejection")
  }
}

///|
test "inventory requires exactly four unique safe compute targets" {
  try
    @installer.validate_request({
      ..valid_request(),
      compute_nodes: [
        { node_name: "dgx-spark-01", ssh_host: "10.0.0.21" },
        { node_name: "dgx-spark-01", ssh_host: "10.0.0.22" },
        { node_name: "dgx-spark-03", ssh_host: "$(touch /tmp/bad)" },
        { node_name: "dgx-spark-04", ssh_host: "10.0.0.24" },
      ],
    })
  catch {
    InvalidField(field) => inspect(field, content="compute_node_name")
  } noraise {
    _ => fail("expected inventory rejection")
  }
}

///|
test "compute target parser accepts name equals host lines" {
  json_inspect(
    @installer.parse_compute_targets(
      "dgx-spark-01=10.0.0.21\ndgx-spark-02=dgx-02.internal\n",
    ),
    content=[
      { "node_name": "dgx-spark-01", "ssh_host": "10.0.0.21" },
      { "node_name": "dgx-spark-02", "ssh_host": "dgx-02.internal" },
    ],
  )
}
