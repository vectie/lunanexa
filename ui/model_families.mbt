///|
/// Presentation only: registry identity, approval and deployment authority stay
/// on the original rows. Unknown families and generations retain their names.
fn model_family(model_id : String) -> String {
  let id = model_id.to_lower()
  if id.contains("qwen") {
    "Qwen"
  } else if id.contains("deepseek") {
    "DeepSeek"
  } else if id.contains("kimi") {
    "Kimi"
  } else if id.contains("glm") {
    "GLM"
  } else if id.contains("stepfun") || id.contains("step-") {
    "StepFun"
  } else if id.contains("minimax") {
    "MiniMax"
  } else {
    "Other"
  }
}

///|
fn model_generation(model_id : String, family : String) -> String {
  let id = model_id.to_lower()
  let marker = match family {
    "Qwen" => "qwen"
    "DeepSeek" => "deepseek"
    "Kimi" => "kimi"
    "GLM" => "glm"
    "StepFun" => "step"
    "MiniMax" => "minimax"
    _ => return model_id
  }
  for part in id.split(marker).drop(1) {
    let suffix = part.trim_start(chars="-_/.")
    let mut version = ""
    for c in suffix {
      if c is ('0'..<='9' | '.' | 'v' | 'k' | 'h' | 'r' | 'm') {
        version += c.to_string()
      } else {
        break
      }
    }
    if version.iter().any(c => c is ('0'..<='9')) {
      return family + " " + version.trim_end(chars=".").to_owned()
    }
  }
  family
}

///|
fn compare_model_generations(left : String, right : String) -> Int32 {
  fn parts(name : String) -> Array[Int32] {
    name
    .split(" ")
    .drop(1)
    .next()
    .unwrap_or("")
    .trim_start(chars="vkhrm")
    .split(".")
    .map(p => @string.parse_int(p.to_owned()) catch { _ => 0 })
    .to_array()
  }
  let a = parts(left)
  let b = parts(right)
  for i in 0..<a.length().max(b.length()) {
    let order = b.get(i).unwrap_or(0).compare(a.get(i).unwrap_or(0))
    if order != 0 {
      return order
    }
  }
  left.compare(right)
}

///|
fn model_family_groups(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.div(
    class="model-registry-groups",
    [
      ..["Qwen", "DeepSeek", "Kimi", "GLM", "StepFun", "MiniMax", "Other"].map(family => {
        let rows = state.models.filter(model => {
          model_family(model.model_id) == family
        })
        if rows.is_empty() {
          return @html.nothing
        }
        let generations : Array[(String, Array[ModelRow])] = []
        for model in rows {
          let name = model_generation(model.model_id, family)
          match generations.iter().find_first(group => group.0 == name) {
            Some(group) => group.1.push(model)
            None => generations.push((name, [model]))
          }
        }
        let count = group_models_by_model_id(rows).length()
        if family != "Other" {
          generations.sort_by((a, b) => compare_model_generations(a.0, b.0))
        }
        @html.details(
          class="model-family",
          open=state.list_pages
            .get(ModelRegistry)
            .map_or(false, page => page.query.trim() != ""),
          [
            @html.summary([
              @html.strong(
                if family == "Other" {
                  localized(state.locale, "Other models", "其他模型")
                } else {
                  family
                },
              ),
              @html.span(class="resource-count", " (\{count})"),
            ]),
            ..generations.map(group => {
              model_registry_group(
                state,
                emit,
                group.0,
                group.1,
                state.list_pages
                .get(ModelRegistry)
                .map_or(false, page => page.query.trim() != ""),
              )
            }),
          ],
        )
      }),
    ],
  )
}
