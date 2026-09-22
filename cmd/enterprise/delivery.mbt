///|
fn delivery_command(
  model : AppModel,
  action : @enterprise_ui.DeliveryMessage?,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.session_generation
  let organization = model.portal.selected_organization_id
  @rabbita.perform(
    result => {
      emit(
        DeliveriesLoaded(
          generation,
          organization,
          model.portal.deliveries.poll_generation,
          result,
        ),
      )
    },
    async fn() noraise {
      try {
        let panel = model.portal.deliveries
        match action {
          Some(Start) => {
            guard @enterprise_ui.selected_delivery_template(panel)
              is Some(template) else {
              raise Failure("template not selected")
            }
            let body : Json = {
              "idempotency_key": panel.idempotency_key,
              "reservation_id": panel.reservation_id,
              "project_id": model.portal.project_id,
              "template_id": template.template_id,
              "template_version": template.template_version,
              "kind": template.kind,
            }
            ignore(
              request(
                "POST",
                model.endpoint,
                "/v1/portal/self/deliveries",
                model.token,
                model.subject_ref,
                body=body.stringify(),
              ),
            )
          }
          Some(Retry(id)) | Some(ConfirmStop(id)) => {
            guard panel.operations
              .iter()
              .find_first(operation => operation.operation_id == id)
              is Some(operation) else {
              raise Failure("operation not found")
            }
            let suffix = if action is Some(Retry(_)) {
              ":retry"
            } else {
              ":stop"
            }
            let body : Json = { "generation": operation.generation.to_string() }
            ignore(
              request(
                "POST",
                model.endpoint,
                "/v1/portal/self/deliveries/\{id}\{suffix}",
                model.token,
                model.subject_ref,
                body=body.stringify(),
              ),
            )
          }
          _ => ()
        }
        let operations : Array[@enterprise_ui.DeliveryView] = @json.from_json(
          @json.parse(
            request(
              "GET",
              model.endpoint,
              "/v1/portal/self/deliveries",
              model.token,
              model.subject_ref,
            ),
          ),
        )
        let (options, option_error) : (@enterprise_ui.DeliveryOptions, String?) = (
          @json.from_json(
            @json.parse(
              request(
                "GET",
                model.endpoint,
                "/v1/portal/self/delivery-options",
                model.token,
                model.subject_ref,
              ),
            ),
          ),
          None,
        ) catch {
          _ =>
            (
              { reservations: [], templates: [], },
              Some(
                portal_copy(
                  model.portal.locale,
                  "Service status loaded, but launch options are unavailable. Check that your resource authorization is active and refresh.",
                  "服务状态已加载，但启动选项暂不可用。请确认资源授权有效后刷新。",
                ),
              ),
            )
        }
        Ok((options, operations, option_error))
      } catch {
        _ =>
          Err(
            portal_copy(
              model.portal.locale,
              "Unable to update the delivery. Refresh its status before retrying; no additional resources are requested by refresh.",
              "无法更新服务交付。请先刷新状态再重试；刷新不会申请额外资源。",
            ),
          )
      }
    },
  )
}

///|
fn delivery_poll_command(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  if model.portal.route != DesktopIde ||
    model.portal.deliveries.error is Some(_) ||
    !model.portal.deliveries.operations.any(operation => {
      operation.stage == "Reserving" ||
      operation.stage == "PreparingModel" ||
      operation.stage == "LoadingModel" ||
      operation.stage == "StartingWorkspace" ||
      operation.stage == "Stopping"
    }) {
    return @rabbita.none
  }
  @rabbita.perform(
    _ => {
      emit(
        DeliveryPollDue(
          model.session_generation,
          model.portal.selected_organization_id,
          model.portal.deliveries.poll_generation,
        ),
      )
    },
    async fn() noraise {
      ignore(contract_preview_delay_promise(5000).wait()) catch {
        _ => ()
      }
    },
  )
}

///|
fn delivery_workspace_command(
  model : AppModel,
  operation_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(result => emit(Outcome(result)), async fn() noraise {
    try {
      guard model.portal.deliveries.operations
        .iter()
        .find_first(operation => {
          operation.operation_id == operation_id &&
          operation.kind == "Workspace" &&
          (operation.stage == "StartingWorkspace" || operation.stage == "Ready")
        })
        is Some(operation) else {
        raise Failure("workspace not ready to start")
      }
      guard model.portal.deliveries.options.templates
        .iter()
        .find_first(template => {
          template.template_id == operation.template_id &&
          template.template_version == operation.template_version &&
          template.kind == "Workspace"
        })
        is Some(template) else {
        raise Failure("template unavailable")
      }
      let clients : Array[DesktopClientResponse] = @json.from_json(
        @json.parse(
          request(
            "GET",
            model.endpoint,
            "/v1/portal/self/clients",
            model.token,
            model.subject_ref,
          ),
        ),
      )
      guard clients.iter().find_first(client => client.client_id == "comfyui")
        is Some(client) else {
        raise Failure("public workspace integration unavailable")
      }
      let body : Json = {
        "request_id": random_identifier("delivery-handoff"),
        "client_id": client.client_id,
        "project_id": model.portal.project_id,
        "allowed_models": [template.model_selector].to_json(),
        "delivery_id": operation_id,
      }
      let launch : DesktopClientHandoffLaunch = @json.from_json(
        @json.parse(
          request(
            "POST",
            model.endpoint,
            "/v1/portal/self/client-handoffs",
            model.token,
            model.subject_ref,
            body=body.stringify(),
          ),
        ),
      )
      if !launch.one_time ||
        launch.client_id != client.client_id ||
        launch.handoff_expires_unix_ms <= current_unix_ms() ||
        !(launch.launch_uri.has_prefix("https://") ||
        launch.launch_uri.has_prefix("http://")) ||
        launch.launch_uri.contains("127.0.0.1") ||
        launch.launch_uri.contains("localhost") ||
        launch.launch_uri.contains("[::1]") {
        raise Failure("public workspace address unavailable")
      }
      open_desktop_client(
        launch.launch_uri,
        launch.client_id,
        launch.handoff_code,
      )
      DesktopClientLaunched(launch.display_name)
    } catch {
      _ =>
        Failed(
          model.portal.locale,
          portal_copy(
            model.portal.locale,
            "Unable to open this delivery's public workspace. Refresh service status and retry.",
            "无法打开此交付的公网工作区。请刷新服务状态后重试。",
          ),
        )
    }
  })
}
