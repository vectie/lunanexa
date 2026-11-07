///|
/// Use artifact identity already returned with assignments; never guess a
/// model from a deployment's arbitrary display name.
fn deployment_model_id(state : ConsoleState, row : DeploymentRow) -> String {
  state.models
  .iter()
  .find_first(m => {
    row.model_digest != "" && m.artifact_digest == row.model_digest
  })
  .map(m => m.model_id)
  .unwrap_or("")
}

///|
fn pool_model_options(
  models : Array[String],
  selected : String,
) -> Array[@rabbita.Html] {
  let groups : Array[(String, Array[String])] = []
  for name in models {
    let family = model_family(name)
    let label = model_generation(name, family)
    match groups.iter().find_first(g => g.0 == label) {
      Some(g) => g.1.push(name)
      None => groups.push((label, [name]))
    }
  }
  groups.sort_by((a, b) => {
    let family = model_family(a.0).compare(model_family(b.0))
    if family == 0 {
      compare_model_generations(a.0, b.0)
    } else {
      family
    }
  })
  groups.map(g => {
    @html.optgroup(
      label=g.0,
      [
        ..g.1.map(name => {
          @html.option(value=name, selected=selected == name, name)
        }),
      ],
    )
  })
}

///|
fn deployment_family_groups(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.div(
    class="model-registry-groups",
    [
      ..["Qwen", "DeepSeek", "Kimi", "GLM", "StepFun", "MiniMax", "Other"].map(family => {
        let rows = state.deployments.filter(r => {
          model_family(deployment_model_id(state, r)) == family
        })
        if rows.is_empty() {
          return @html.nothing
        }
        let generations : Array[(String, Array[DeploymentRow])] = []
        for row in rows {
          let id = deployment_model_id(state, row)
          let name = if id == "" {
            localized(state.locale, "Unidentified model", "未识别模型")
          } else {
            model_generation(id, family)
          }
          match generations.iter().find_first(g => g.0 == name) {
            Some(g) => g.1.push(row)
            None => generations.push((name, [row]))
          }
        }
        generations.sort_by((a, b) => compare_model_generations(a.0, b.0))
        @html.details(
          class="model-family",
          open=true,
          [
            @html.summary(
              if family == "Other" {
                localized(state.locale, "Other deployments", "其他部署")
              } else {
                family
              },
            ),
            ..generations.map(g => {
              @html.details(class="model-registry-group", open=true, [
                @html.summary(g.0 + " (" + g.1.length().to_string() + ")"),
                @html.div(class="table-scroll", [
                  @html.table(class="resource-table model-service-table", [
                    @html.thead(
                      @html.tr([
                        @html.th(localized(state.locale, "Service", "服务")),
                        @html.th(localized(state.locale, "Status", "状态")),
                        @html.th(localized(state.locale, "Resource", "资源")),
                        @html.th(localized(state.locale, "Action", "操作")),
                      ]),
                    ),
                    @html.tbody(
                      [
                        ..g.1.map(row => {
                          deployment_item(state.locale, row, emit)
                        }),
                      ],
                    ),
                  ]),
                ]),
              ])
            }),
          ],
        )
      }),
    ],
  )
}
