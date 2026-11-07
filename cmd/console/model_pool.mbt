///|
fn update_model_pool(
  model : AppModel,
  action : String,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  if action.has_prefix("service-start/") {
    return start_model_service(
      model,
      action["service-start/".length():].to_owned(),
      emit,
    )
  }
  guard model.console.operator_authenticated &&
    !model.demo_mode &&
    !model.console.loading &&
    [
      "adopt", "prepare", "switch", "activate", "rollback", "benchmark", "speculative",
      "speculative-off", "tuning", "benchmark-cold", "benchmark-repeat", "export",
      "scope", "benchmark-fixed",
    ].contains(action) else {
    return (model, @rabbita.none)
  }
  let panel = model.console.model_pool
  let selected = if panel.model == "" {
    panel.view.map_or("", v => v.model)
  } else {
    panel.model
  }
  let speculative = if action == "speculative-off" {
    0
  } else if panel.speculative_tokens == "" {
    panel.view.map_or(0, p => p.speculative_tokens)
  } else {
    @string.parse_int(panel.speculative_tokens) catch {
      _ => -1
    }
  }
  let endpoint_action = if action == "speculative-off" {
    "speculative"
  } else if action.has_prefix("benchmark-") {
    "benchmark"
  } else {
    action
  }
  let command = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try {
      let tuning = panel.view.map_or(@ui.default_model_tuning(), v => v.tuning)
      let draft = panel.tuning_draft
      let body : Json = if action == "scope" {
        let pool = panel.view.unwrap()
        {
          "node_ids": Json(@ui.pool_scope_nodes(panel, pool)),
          "names": Json(@ui.pool_scope_names(panel, pool)),
        }
      } else if action == "tuning" {
        let fields : Map[String, Json] = {
          "cache_aware_routing": Json(
            draft
            .get("cache_aware_routing")
            .unwrap_or(@ui.tuning_value(tuning, "cache_aware_routing")) ==
            "on",
          ),
          "max_num_batched_tokens": Json(
            @string.parse_int(
              draft
              .get("max_num_batched_tokens")
              .unwrap_or(tuning.max_num_batched_tokens.to_string()),
            ),
          ),
        }
        for key in ["prefix_caching", "chunked_prefill"] {
          let value = draft.get(key).unwrap_or(@ui.tuning_value(tuning, key))
          if value != "auto" {
            fields[key] = Json(value == "on")
          }
        }
        Json(fields)
      } else {
        {
          "model": selected,
          "speculative_tokens": Json(speculative),
          "profile": if action == "benchmark-cold" {
            "cold"
          } else if action == "benchmark-repeat" {
            "repeat"
          } else if action == "benchmark-fixed" {
            "fixed"
          } else {
            "short"
          },
        }
      }
      if action == "export" {
        let raw = request(
          "GET",
          model.endpoint,
          "/v1/model-pool",
          model.credential,
        )
        let evidence = @json.parse(raw)
        guard evidence is { "replicas": Array(_), "benchmark": _, .. } else {
          fail("测速证据格式无效")
        }
        download_json_file(
          "model-pool-evidence-\{current_unix_ms()}.json",
          evidence.stringify(),
        )
      } else {
        ignore(
          request(
            "POST",
            model.endpoint,
            "/v1/model-pool:" + endpoint_action,
            model.credential,
            body=body.stringify(),
          ),
        )
      }
    } catch {
      error => {
        let detail = error.to_string()
        ActionFailed(
          model.console.locale,
          "模型池操作尚未完成：" +
          detail[:detail.length().min(600)].to_owned() +
          "。请按原因处理后刷新状态；原模型回滚配置仍保留。",
        )
      }
    } noraise {
      _ =>
        ActionComplete(
          model.console.locale,
          if action == "export" {
            "已导出本轮、上轮和模型池配置的完整测速证据。"
          } else {
            "模型池操作已提交。请以各节点的权重与实际模型就绪状态为准。"
          },
        )
    }
  })
  (
    {
      ..model,
      console: {
        ..model.console,
        loading: true,
        error_message: None,
        success_message: None,
      },
    },
    command,
  )
}

///|
fn start_model_service(
  model : AppModel,
  id : String,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard model.console.operator_authenticated &&
    !model.demo_mode &&
    !model.console.loading else {
    return (model, @rabbita.none)
  }
  let cmd = @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
    try
      request(
        "POST",
        model.endpoint,
        "/v1/model-services/" + id + ":start",
        model.credential,
      )
    catch {
      _ =>
        ActionFailed(
          model.console.locale,
          console_copy(
            model.console.locale,
            "Service start was rejected. Check resource ownership and refresh.",
            "启动未完成，请检查资源归属并刷新状态。",
          ),
        )
    } noraise {
      _ =>
        ActionComplete(
          model.console.locale,
          console_copy(
            model.console.locale,
            "Start requested. Waiting for runtime readiness.",
            "已请求启动，等待运行实例就绪。",
          ),
        )
    }
  })
  ({ ..model, console: { ..model.console, loading: true, }, }, cmd)
}
