///|
fn valid_request(apply? : Bool = false) -> @installer.InstallRequest {
  {
    version: @installer.request_version,
    deployment_target: ManagementAndCompute,
    apply,
    confirmation: if apply {
      @installer.management_and_compute_confirmation
    } else {
      ""
    },
    ssh_user: "cluster-admin",
    ssh_port: 22,
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
    management_secret_manifest: "/srv/lunanexa/secrets/management.yaml",
    secret_directory: "/srv/lunanexa/secrets",
    cli_path: "/usr/local/bin/lunanexa",
  }
}

///|
test "local simulation requires only its isolated kubeconfig and confirmation" {
  let request = {
    ..valid_request(apply=true),
    deployment_target: LocalSimulation,
    confirmation: @installer.simulation_confirmation,
    kubeconfig_path: "~/.kube/lunanexa-sim",
    ssh_user: "",
    ssh_key_path: "",
    known_hosts_path: "",
    management_node: "",
    management_host: "",
    compute_nodes: [],
    rendered_directory: "",
    management_secret_manifest: "",
    secret_directory: "",
    cli_path: "",
  }
  @installer.validate_request(request)
}

///|
test "valid dry-run and confirmed apply requests" {
  @installer.validate_request(valid_request())
  @installer.validate_request(valid_request(apply=true))
}

///|
test "management foundation does not require compute inventory" {
  @installer.validate_request({
    ..valid_request(apply=true),
    deployment_target: ManagementFoundation,
    confirmation: @installer.management_confirmation,
    compute_nodes: [],
    secret_directory: "",
    cli_path: "",
  })
}

///|
test "compute expansion accepts a selected subset" {
  @installer.validate_request({
    ..valid_request(apply=true),
    deployment_target: ComputeExpansion,
    confirmation: @installer.compute_confirmation,
    compute_nodes: [{ node_name: "compute-01", ssh_host: "10.0.0.21" }],
  })
}

///|
test "compute expansion does not require management host identity" {
  @installer.validate_request({
    ..valid_request(apply=true),
    deployment_target: ComputeExpansion,
    confirmation: @installer.compute_confirmation,
    management_node: "",
    management_host: "",
    compute_nodes: [{ node_name: "compute-01", ssh_host: "10.0.0.21" }],
    management_secret_manifest: "",
  })
}

///|
test "displayed stage counts match each executable deployment scope" {
  assert_eq(@installer.stage_names(ManagementFoundation).length(), 6)
  assert_eq(@installer.stage_names(ComputeExpansion).length(), 7)
  assert_eq(@installer.stage_names(ManagementAndCompute).length(), 10)
  assert_eq(@installer.stage_names(LocalSimulation).length(), 5)
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
test "selected inventory rejects duplicate and unsafe compute targets" {
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
test "combined deployment accepts non-four inventory and explicit co-location" {
  @installer.validate_request({
    ..valid_request(),
    management_node: "lab-01",
    management_host: "lab-01.internal",
    compute_nodes: [{ node_name: "lab-01", ssh_host: "lab-01.internal" }],
  })
  @installer.validate_request({
    ..valid_request(),
    compute_nodes: [
      { node_name: "compute-a", ssh_host: "10.0.0.21" },
      { node_name: "compute-b", ssh_host: "10.0.0.22" },
      { node_name: "compute-c", ssh_host: "10.0.0.23" },
    ],
  })
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
