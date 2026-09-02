///|
test "installer renders guarded bilingual deployment workflow" {
  let english = @installer.default_state(locale=English)
  let english_html = @installer.render(english)
  assert_true(english_html.contains("Deploy LunaNexa"))
  assert_true(english_html.contains("Management foundation"))
  assert_true(english_html.contains("Dry-run first"))
  assert_true(english_html.contains("StrictHostKeyChecking=yes"))
  assert_true(english_html.contains("type=\"password\""))
  assert_true(english_html.contains("disabled"))
  let chinese = @installer.update(english, LocaleChanged(ChineseSimplified))
  let chinese_html = @installer.render(chinese)
  assert_true(chinese_html.contains("部署 LunaNexa"))
  assert_true(chinese_html.contains("先预检"))
  assert_true(
    chinese_html.contains("通过固定 SSH 身份检查所选管理主机"),
  )
  assert_true(
    chinese_html.contains("验证 Kubernetes 上下文并预览变更"),
  )
}

///|
test "terminal keeps a bounded tail and run state is explicit" {
  let mut state = @installer.default_state(locale=English)
  state = @installer.update(state, PreviewRequested)
  assert_true(@installer.is_running(state))
  for index in 0..<510 {
    state = @installer.update(state, TerminalLine("line-\{index}"))
  }
  assert_eq(state.terminal_lines.length(), 500)
  state = @installer.update(state, RunFinished(true, 0))
  assert_false(@installer.is_running(state))
  assert_true(state.preview_verified)
  state = @installer.update(state, ManagementHostChanged("10.0.0.11"))
  assert_false(state.preview_verified)
  assert_true(@installer.render(state).contains("Completed"))
}

///|
test "a rejected rerun cannot leave stale success in the terminal" {
  let mut state = @installer.default_state(locale=English)
  state = @installer.update(state, PreviewRequested)
  state = @installer.update(state, TerminalLine("[preview] safe dry run"))
  state = @installer.update(state, RunFinished(true, 0))
  assert_true(state.terminal_lines.join("\n").contains("[complete]"))
  state = @installer.update(state, RunRejected("Deployment could not start."))
  let terminal = state.terminal_lines.join("\n")
  assert_false(terminal.contains("[complete]"))
  assert_false(terminal.contains("safe dry run"))
  assert_true(terminal.contains("[blocked]"))
  assert_false(state.preview_verified)
  assert_eq(state.run_state, Failed)
}

///|
test "local Colima mode needs only companion session and isolated kubeconfig" {
  let mut state = @installer.default_state(locale=English)
  state = @installer.update(
    state,
    SessionTokenChanged("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  state = @installer.update(state, DeploymentTargetChanged("local-colima"))
  assert_eq(state.form.deployment_target, LocalSimulation)
  assert_eq(state.form.kubeconfig_path, "~/.kube/lunanexa-sim")
  assert_true(@installer.form_complete(state))
  let html = @installer.render(state)
  assert_true(html.contains("Local Colima simulation"))
  assert_true(html.contains("Reconcile simulation"))
  assert_true(html.contains("Verify dedicated Colima profile"))
}

///|
test "management and compute scopes expose only their own inventory" {
  let management = @installer.default_state(locale=English)
  let management_html = @installer.render(management)
  assert_true(management_html.contains("Deploy management foundation"))
  assert_true(management_html.contains("DEPLOY MANAGEMENT"))
  assert_true(management_html.contains("Protected management secret manifest"))
  assert_true(management_html.contains("simulation-hidden"))
  let compute = @installer.update(
    management,
    DeploymentTargetChanged("compute-expansion"),
  )
  let compute_html = @installer.render(compute)
  assert_true(
    compute_html.contains("Selected compute nodes · node-name=ssh-host"),
  )
  assert_true(compute_html.contains("ADD COMPUTE"))
  assert_true(compute_html.contains("simulation-hidden"))
  assert_eq(compute.form.management_node, "")
  assert_eq(compute.form.management_host, "")
}

///|
test "installer exposes no access-node field or fixed compute count" {
  let combined = @installer.update(
    @installer.default_state(locale=English),
    DeploymentTargetChanged("management-and-compute"),
  )
  let html = @installer.render(combined)
  assert_false(html.contains("Access node"))
  assert_false(html.contains("Bastion host"))
  assert_false(html.contains("Four compute nodes"))
  assert_true(html.contains("Selected compute nodes"))
  assert_eq(combined.form.compute_targets, "")
}

///|
test "scope switching cannot leak hidden topology values" {
  let initial = @installer.default_state(locale=English)
  let combined = @installer.update(
    initial,
    DeploymentTargetChanged("management-and-compute"),
  )
  let combined = @installer.update(
    combined,
    ManagementSecretManifestChanged("/secrets/management.yaml"),
  )
  let combined = @installer.update(
    combined,
    ComputeTargetsChanged("compute-01=10.0.0.21"),
  )
  assert_eq(combined.form.compute_targets, "compute-01=10.0.0.21")
  let simulation = @installer.update(
    combined,
    DeploymentTargetChanged("local-colima"),
  )
  assert_eq(simulation.form.compute_targets, "")
  assert_eq(simulation.form.kubeconfig_path, "~/.kube/lunanexa-sim")
  assert_eq(simulation.form.management_secret_manifest, "")
  let management = @installer.update(
    simulation,
    DeploymentTargetChanged("management-foundation"),
  )
  assert_eq(management.form.compute_targets, "")
  assert_eq(management.form.kubeconfig_path, "")
  assert_eq(management.form.confirmation, "")
}

///|
test "compute-only scope has no hidden management-host requirement" {
  let mut state = @installer.default_state(locale=English)
  state = @installer.update(
    state,
    SessionTokenChanged("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  state = @installer.update(state, DeploymentTargetChanged("compute-expansion"))
  state = @installer.update(state, SshKeyPathChanged("/keys/operator"))
  state = @installer.update(state, KnownHostsPathChanged("/keys/known_hosts"))
  state = @installer.update(state, KubeconfigPathChanged("/kube/config"))
  state = @installer.update(state, RenderedDirectoryChanged("/rendered"))
  state = @installer.update(state, SecretDirectoryChanged("/secrets"))
  state = @installer.update(state, CliPathChanged("/bin/lunanexa"))
  state = @installer.update(
    state,
    ComputeTargetsChanged("compute-01=compute-direct"),
  )
  assert_eq(state.form.management_node, "")
  assert_eq(state.form.management_host, "")
  assert_true(@installer.form_complete(state))
}
