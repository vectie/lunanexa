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
          Some(ActivateCompanyWorkspace) =>
            ignore(
              request(
                "POST",
                model.endpoint,
                "/v1/portal/self/undertaking-workspace",
                model.token,
                model.subject_ref,
                body="{}",
              ),
            )
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
          Some(ConfirmStopExternal) =>
            ignore(
              request(
                "POST",
                model.endpoint,
                "/v1/portal/self/model-services/" +
                panel.external_model.unwrap().service_id +
                ":stop",
                model.token,
                model.subject_ref,
                body="{}",
              ),
            )
          Some(ConfirmStartExternal) =>
            ignore(
              request(
                "POST",
                model.endpoint,
                "/v1/portal/self/model-services/" +
                panel.external_model.unwrap().service_id +
                ":start",
                model.token,
                model.subject_ref,
                body="{}",
              ),
            )
          _ => ()
        }
        // Enterprise model control belongs to the organization administrator;
        // personal deliveries require Developer access. A missing personal
        // lease must not hide the shared model's status or stop action.
        let operations : Array[@enterprise_ui.DeliveryView] = try
          @json.from_json(
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
        catch {
          error if error.to_string().contains("HTTP 401") => raise error
          _ => panel.operations
        } noraise {
          value => value
        }
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
          error if error.to_string().contains("HTTP 401") => raise error
          _ =>
            (
              { reservations: [], templates: [], shared_trials: [], },
              Some(
                portal_copy(
                  model.portal.locale,
                  "Service status loaded, but launch options are temporarily unavailable. Refresh to retry.",
                  "服务状态已加载，启动选项暂不可用。请刷新重试。",
                ),
              ),
            )
        }
        // Every route that shows the company model or selects it for a workspace
        // must load its status on direct entry, without requiring a MaaS visit.
        let (external_model, shared_models, external_error) : (
          @enterprise_ui.ExternalModelServiceView?,
          Array[@enterprise_ui.ExternalModelServiceView],
          String?,
        ) = if model.portal.route == Models ||
          model.portal.route == Overview ||
          model.portal.route == MachineAccess ||
          model.portal.route == DesktopIde {
          try {
            let services : Array[@enterprise_ui.ExternalModelServiceView] = @json.from_json(
              @json.parse(
                request(
                  "GET",
                  model.endpoint,
                  "/v1/portal/self/model-services",
                  model.token,
                  model.subject_ref,
                ),
              ),
            )
            let previous = match panel.external_model {
              Some(previous) =>
                services
                .iter()
                .find_first(s => s.service_id == previous.service_id)
              None => None
            }
            let selected = match previous {
              Some(_) => previous
              None =>
                match services.iter().find_first(s => s.ready) {
                  Some(service) => Some(service)
                  None => services.get(0)
                }
            }
            (selected, services, None)
          } catch {
            error if error.to_string().contains("HTTP 401") => raise error
            error if error.to_string().contains("HTTP 404 NotFound") =>
              (None, [], None)
            _ =>
              (
                panel.external_model.map(service => {
                  ..service,
                  state: "Unavailable",
                  ready: false,
                  can_stop: false,
                }),
                panel.shared_models.map(service => {
                  ..service,
                  state: "Unavailable",
                  ready: false,
                  can_stop: false,
                }),
                Some(
                  portal_copy(
                    model.portal.locale,
                    "Model service status is currently unavailable. Refresh to retry.",
                    "模型服务状态暂不可用，请刷新重试。",
                  ),
                ),
              )
          } noraise {
            value => value
          }
        } else {
          (panel.external_model, panel.shared_models, None)
        }
        let status_error = match external_error {
          Some(_) => external_error
          None => option_error
        }
        let company_workspace : @enterprise_ui.CompanyWorkspaceStatus? = try
          Some(
            @json.from_json(
              @json.parse(
                request(
                  "GET",
                  model.endpoint,
                  "/v1/portal/self/undertaking-workspace",
                  model.token,
                  model.subject_ref,
                ),
              ),
            ),
          )
        catch {
          error if error.to_string().contains("HTTP 401") => raise error
          _ => None
        } noraise {
          value => value
        }
        Ok(
          (
            options, operations, external_model, shared_models, company_workspace,
            status_error,
          ),
        )
      } catch {
        error if error.to_string().contains("HTTP 401") =>
          Err("HTTP 401 Unauthenticated")
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
  if (
      model.portal.route != DesktopIde &&
      model.portal.route != MachineAccess &&
      model.portal.route != Models &&
      model.portal.route != Overview
    ) ||
    model.portal.deliveries.error is Some(_) ||
    (
      !model.portal.deliveries.operations.any(operation => {
        operation.stage == "Reserving" ||
        operation.stage == "PreparingModel" ||
        operation.stage == "LoadingModel" ||
        operation.stage == "StartingWorkspace" ||
        operation.stage == "Stopping"
      }) &&
      !(model.portal.route == Models &&
      model.portal.deliveries.external_model.map_or(false, service => {
        service.state == "Running" && !service.ready
      }))
    ) {
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
  @rabbita.perform(
    result => {
      emit(
        Outcome(
          ApplicationLaunchCompleted(
            model.session_generation,
            model.portal.selected_organization_id,
            Some(model.portal.deliveries.poll_generation),
            result,
          ),
        ),
      )
    },
    async fn() noraise {
      try {
        guard @enterprise_ui.delivery_launch_template(
            model.portal.deliveries,
            operation_id,
          )
          is Some(template) &&
          template.client_id is Some(client_id) else {
          raise Failure("interactive delivery unavailable")
        }
        guard model.portal.deliveries.operations
          .iter()
          .find_first(operation => operation.operation_id == operation_id)
          is Some(operation) else {
          raise Failure("delivery unavailable")
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
        guard clients.iter().find_first(client => client.client_id == client_id)
          is Some(client) else {
          raise Failure("public workspace integration unavailable")
        }
        let body : Json = {
          "request_id": random_identifier("delivery-handoff"),
          "client_id": client.client_id,
          "project_id": operation.project_id,
          "allowed_models": Json(
            if template.kind == "GpuContainer" {
              ([] : Array[String])
            } else {
              [template.model_selector]
            },
          ),
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
          (
            template.kind != "ModelApi" &&
            (
              launch.launch_uri.contains("127.0.0.1") ||
              launch.launch_uri.contains("localhost") ||
              launch.launch_uri.contains("[::1]")
            )
          ) {
          raise Failure("public workspace address unavailable")
        }
        open_desktop_client(
          launch.launch_uri,
          launch.client_id,
          launch.handoff_code,
          false,
        )
        Ok(launch.display_name)
      } catch {
        _ =>
          Err(
            portal_copy(
              model.portal.locale,
              "Unable to open this delivery's public workspace or terminal. Refresh service status and retry.",
              "无法打开此交付的公网工作区或终端。请刷新服务状态后重试。",
            ),
          )
      }
    },
  )
}

///|
fn delivery_api_access_command(
  model : AppModel,
  operation_id : String,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(
    result => {
      emit(
        DeliveryAccessIssued(
          model.session_generation,
          model.portal.selected_organization_id,
          model.portal.deliveries.poll_generation,
          result,
        ),
      )
    },
    async fn() noraise {
      try {
        guard model.portal.deliveries.operations.any(operation => {
          operation.operation_id == operation_id &&
          operation.kind == "ModelApi" &&
          operation.stage == "Ready"
        }) else {
          raise Failure("model delivery not ready")
        }
        let body : Json = { "request_id": random_identifier("delivery-key") }
        let access : @enterprise_ui.DeliveryApiAccess = @json.from_json(
          @json.parse(
            request(
              "POST",
              model.endpoint,
              "/v1/portal/self/deliveries/\{operation_id}/access-key",
              model.token,
              model.subject_ref,
              body=body.stringify(),
            ),
          ),
        )
        if !access.one_time ||
          access.delivery_id != operation_id ||
          access.expires_unix_ms <= current_unix_ms() {
          raise Failure("invalid delivery access response")
        }
        Ok(access)
      } catch {
        _ =>
          Err(
            portal_copy(
              model.portal.locale,
              "Unable to issue the delivery API key. Refresh the delivery status before trying again. A key is never automatically reissued.",
              "无法签发交付 API 密钥。请刷新交付状态后重试；系统不会自动重复签发密钥。",
            ),
          )
      }
    },
  )
}
