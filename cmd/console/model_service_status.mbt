///|
/// A running process is not evidence that its inference endpoint is ready.
fn model_service_deployment_row(value : Json) -> @ui.DeploymentRow raise {
  let service : @deployment.ModelServiceInstance = @json.from_json(value)
  let ready = value is { "ready": True, .. }
  {
    assignment_id: "service:" + service.service_id,
    deployment_id: service.model_alias,
    desired: if service.desired_running {
      Ready
    } else {
      Stopped
    },
    observed: match service.observed {
      Running => if ready { Ready } else { Starting }
      Stopped => Stopped
      Partial => Degraded
      Unknown => Preparing
    },
    placement_reason: "#\{service.generation}",
    model_digest: service.artifact_digest,
    node_id: service.node_ids.join(" · "),
    resource_owner: service.owner.tenant_ref,
  }
}

///|
/// Reuse the existing cluster tick only while a visible service is loading.
/// One outstanding read at a time; ready/stopped rows add no idle polling.
fn refresh_starting_model_services(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard model.console.route == Deployments &&
    model.console.operator_authenticated &&
    !model.demo_mode &&
    model.console_read_groups.get(DeploymentReads) == Some(true) &&
    model.console.deployments.any(row => {
      row.assignment_id.has_prefix("service:") && row.observed == Starting
    }) else {
    return (model, @rabbita.none)
  }
  let groups = model.console_read_groups.copy()
  groups.set(DeploymentReads, false)
  (
    { ..model, console_read_groups: groups, },
    deferred_read_command(model, DeploymentReads, emit),
  )
}
