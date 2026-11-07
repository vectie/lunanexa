///|
pub(all) struct ModelTuning {
  prefix_caching : Bool?
  cache_aware_routing : Bool
  chunked_prefill : Bool?
  max_num_batched_tokens : Int32
} derive(Eq, FromJson)

///|
pub extend ModelTuning with Eq::{equal, not_equal}

///|
pub extend ModelTuning with FromJson::{from_json}

///|
pub fn default_model_tuning() -> ModelTuning {
  {
    prefix_caching: None,
    cache_aware_routing: false,
    chunked_prefill: None,
    max_num_batched_tokens: 0,
  }
}

///|
pub fn tuning_value(tuning : ModelTuning, key : String) -> String {
  match key {
    "prefix_caching" =>
      match tuning.prefix_caching {
        Some(true) => "on"
        Some(false) => "off"
        None => "auto"
      }
    "cache_aware_routing" =>
      if tuning.cache_aware_routing {
        "on"
      } else {
        "off"
      }
    "chunked_prefill" =>
      if tuning.chunked_prefill == Some(true) {
        "on"
      } else {
        "auto"
      }
    "max_num_batched_tokens" => tuning.max_num_batched_tokens.to_string()
    _ => ""
  }
}

///|
fn tuning_label(tuning : ModelTuning) -> String {
  "前缀 " +
  tuning_value(tuning, "prefix_caching") +
  " · 路由 " +
  (if tuning.cache_aware_routing { "缓存亲和" } else { "最少负载" }) +
  " · 分块 " +
  tuning_value(tuning, "chunked_prefill") +
  " · 批 token " +
  (if tuning.max_num_batched_tokens == 0 {
    "自动"
  } else {
    tuning.max_num_batched_tokens.to_string()
  })
}

///|
fn tuning_panel(
  state : ConsoleState,
  pool : ModelPoolView,
  disabled : Bool,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let unavailable = disabled ||
    !pool.adopted ||
    pool.model == "" ||
    pool.benchmark.map_or(false, b => ["running", "queued"].contains(b.status))
  @html.section(class="model-benchmark-panel", [
    @html.h3("前缀缓存与预填充"),
    @html.p(
      "目标：" +
      tuning_label(pool.tuning) +
      " · 已生效 \{pool.participating().count_if(r => r.configuration_ready && r.ready)}/\{pool.participating().length()} 台",
    ),
    @html.div(
      class="model-pool-grid",
      [
        for
          (key, label, options) in [
            (
              "prefix_caching",
              "前缀缓存",
              [
                ("auto", "运行时默认"),
                ("off", "关闭（对照）"),
                ("on", "开启"),
              ],
            ),
            (
              "cache_aware_routing",
              "请求路由",
              [("off", "最少负载"), ("on", "缓存亲和 + 负载回退")],
            ),
            (
              "chunked_prefill",
              "分块预填充",
              [("auto", "运行时默认"), ("on", "显式开启")],
            ),
            (
              "max_num_batched_tokens",
              "每步 token 预算（不是并发上限）",
              [
                ("0", "自动"),
                ("512", "512"),
                ("1024", "1024"),
                ("2048", "2048"),
                ("4096", "4096"),
                ("8192", "8192"),
                ("16384", "16384"),
              ],
            ),
          ] => {
          let value = state.model_pool.tuning_draft
            .get(key)
            .unwrap_or(tuning_value(pool.tuning, key))
          @html.div([
            @html.label(for_="pool-" + key, label),
            @html.select(
              id="pool-" + key,
              attrs=@html.Attrs::build().disabled(unavailable),
              on_change=text_command(emit, v => ModelPoolTuningSelect(key, v)),
              [
                for (v, text) in options => {
                  @html.option(value=v, selected=value == v, text)
                }
              ],
            ),
          ])
        }
      ],
    ),
    @html.p(
      class="secondary",
      "仅改路由无需重启；其余配置会重启参与节点并清空缓存。缓存亲和只预测可复用前缀，不代表实际命中；按租户隔离，忙时退回最少负载，不加并发限制。保持模型精度、上下文长度和采样不变。仅显式设置 runtime_prefix_cache: true 的请求允许临时 GPU 前缀复用，不保存原文或缓存回答；下方合成测试会携带此选项。",
    ),
    @html.p(
      class="secondary",
      "质量提示：缓存 + MTP 必须逐项对照，速度达标不代表质量通过。当前 Qwen3.6 混合架构组合仍属实验项；出现新增错误应恢复对照配置并复核。当前参与节点模型的对齐缓存页超过 1024 token，显式批 token 预算请选 2048 或以上；自动预算不受影响。",
    ),
    @html.button(
      disabled=unavailable,
      on_click=command(emit, ModelPoolAction("tuning")),
      "应用缓存与预填充配置",
    ),
  ])
}
