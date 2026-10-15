///|
fn send(emit : @rabbita.Emit[Message]?, message : Message) -> @rabbita.Cmd {
  match emit {
    Some(emit) => emit(message)
    None => @rabbita.none
  }
}

///|
fn text_emit(
  emit : @rabbita.Emit[Message]?,
  wrap : (String) -> Message,
) -> @rabbita.Emit[String] {
  match emit {
    Some(emit) => emit.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn field(
  id : String,
  label : String,
  value : String,
  field : Field,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  @html.div([
    @html.label(for_=id, label),
    @html.input(
      id~,
      value~,
      maxlength=512,
      on_input=text_emit(emit, value => Edit(field, value)),
    ),
  ])
}

///|
fn origin_label(origin : @planning.Origin) -> String {
  match origin {
    SyntheticFixture => "SYNTHETIC FIXTURE · no physical measurement"
    LocalObservation => "LOCAL OBSERVATION · operator-declared, unverified"
  }
}

///|
/// Typed benchmark authoring; read-only effects stay in the console host.
pub fn view(
  state : State,
  locale : @i18n.Locale,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  let d = state.draft
  @html.section(
    class="capacity-planner",
    attrs=@html.Attrs::build().aria_labelledby("capacity-planner-title"),
    [
      @html.style_tag(
        ".capacity-planner{margin-top:1.5rem;padding:1rem;border:1px solid var(--line);border-radius:.8rem}.capacity-planner h3{margin-top:1.2rem}.capacity-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem}.capacity-planner label{display:block;margin:.4rem 0}.capacity-planner input,.capacity-planner textarea,.capacity-planner select{box-sizing:border-box;width:100%;padding:.65rem;border:1px solid var(--line);border-radius:.4rem;background:var(--panel);color:var(--ink);font:inherit}.capacity-planner textarea{font-family:monospace}.capacity-planner button:not(.ln-icon-button),.capacity-planner a{display:inline-block;margin:.6rem .5rem .6rem 0;padding:.65rem;border:1px solid var(--line);border-radius:.4rem;cursor:pointer}.capacity-run{padding:.75rem;margin:.5rem 0;border:1px solid var(--line);overflow-wrap:anywhere}.capacity-table{overflow-x:auto}.capacity-table table{width:100%;border-collapse:collapse}.capacity-table th,.capacity-table td{text-align:left;padding:.65rem;border-bottom:1px solid var(--line)}.capacity-id{overflow-wrap:anywhere}.capacity-boundary{padding:.75rem;border-left:3px solid var(--amber);color:var(--muted)}@media(max-width:52rem){.capacity-grid{grid-template-columns:1fr}}",
      ),
      @html.style_tag(@controls.styles()),
      @html.h2(
        id="capacity-planner-title",
        @i18n.copy(locale, "Capacity-plan workbench", "容量规划工作台"),
      ),
      @html.p(
        class="capacity-boundary",
        @i18n.copy(
          locale, "Planning only; no resources are reserved. Drafts stay in this tab—download your plan before closing.",
          "仅用于规划，不预留资源。草稿保存在当前标签页，关闭前请下载。",
        ),
      ),
      match state.error {
        Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
        None => @html.nothing
      },
      recorded_view(state, emit),
      csv_view(state, emit),
      @html.details([
        @html.summary("Advanced: paste complete evidence JSON"),
        @html.p(
          "Paste a JSON array of evidence records (run, origin, source_ref, workload_ref, output_unit, memory_total_mib, memory_peak_mib). Up to 8 runs, 10000 samples each, 4 Mi characters. SyntheticFixture and LocalObservation are explicit origin values. Import replaces the draft source list only after validation.",
        ),
        @html.label(for_="capacity-import", "Benchmark evidence JSON"),
        @html.textarea(
          id="capacity-import",
          value=state.import_text,
          rows=6,
          maxlength=4194304,
          on_input=text_emit(emit, value => ImportTextChanged(value)),
          "",
        ),
        @html.button(
          type_="button",
          on_click=send(emit, ImportEvidence),
          @i18n.copy(locale, "Import benchmark evidence", "导入基准证据"),
        ),
      ]),
      @html.h3("Selected comparison evidence"),
      @html.div(
        [
          for evidence in state.sources => {
            if captured_changed(state, evidence) {
              @html.p(
                attrs=@html.Attrs::build().role("status"),
                "Captured run \{evidence.run.run_id} changed or disappeared from current history. Its previous samples and packet are retained; select the current run explicitly to replace it.",
              )
            } else {
              @html.nothing
            }
          }
        ],
      ),
      @html.div(
        [
          for evidence in state.sources => {
            @html.article(class="capacity-run", [
              @html.strong(evidence.run.run_id),
              @html.p(origin_label(evidence.origin)),
              @html.details([
                @html.summary("Evidence identity and measurement context"),
                @html.p(
                  "\{evidence.run.profile} · \{evidence.run.model_digest} · \{evidence.run.runtime_digest} · \{evidence.run.hardware_profile}",
                ),
                @html.p(
                  "\{Repr(evidence.run.kind)} · tested concurrency \{evidence.run.concurrency} · \{evidence.run.samples.length()} samples · \{evidence.output_unit} · \{evidence.workload_ref}",
                ),
                @html.p(
                  "Source: \{evidence.source_ref} · memory peak / total: \{evidence.memory_peak_mib} / \{evidence.memory_total_mib} MiB",
                ),
              ]),
              @html.button(
                type_="button",
                on_click=send(emit, ExploreRun(evidence.run.run_id)),
                "Inspect samples",
              ),
              @html.button(
                type_="button",
                attrs=@html.Attrs::build().aria_pressed(
                  if state.selected.contains(evidence.run.run_id) {
                    "true"
                  } else {
                    "false"
                  },
                ),
                on_click=send(emit, ToggleRun(evidence.run.run_id)),
                if state.selected.contains(evidence.run.run_id) {
                  "Selected · remove from comparison"
                } else {
                  "Select for comparison"
                },
              ),
            ])
          }
        ],
      ),
      explorer_view(state, emit),
      @html.h3(
        @i18n.copy(
          locale, "2. Declare objective and workload", "2. 声明目标与工作负载",
        ),
      ),
      @html.p(
        @i18n.copy(
          locale, "Compare matching workloads from the same evidence source.", "仅比较同一证据来源的匹配工作负载。",
        ),
      ),
      @html.details([
        @html.summary("Workload identity (filled from the first selected run)"),
        @html.div(class="capacity-grid", [
          field("capacity-profile", "Profile", d.profile, Profile, emit),
          field(
            "capacity-model",
            "Model artifact digest",
            d.model_digest,
            ModelDigest,
            emit,
          ),
          field(
            "capacity-runtime",
            "Runtime image digest",
            d.runtime_digest,
            RuntimeDigest,
            emit,
          ),
          field(
            "capacity-hardware",
            "Hardware profile (include driver/topology revision)",
            d.hardware_profile,
            HardwareProfile,
            emit,
          ),
          field(
            "capacity-workload",
            "Exact workload / dataset revision reference",
            d.workload_ref,
            WorkloadRef,
            emit,
          ),
          field("capacity-unit", "Output unit", d.output_unit, OutputUnit, emit),
          @html.div([
            @html.label(for_="capacity-kind", "Benchmark kind"),
            @html.select(
              id="capacity-kind",
              on_change=text_emit(emit, value => Edit(Kind, value)),
              [
                for
                  value in [
                    "Concurrency", "Saturation", "ColdStart", "LongStream", "MixedWorkload",
                  ] => @html.option(value~, selected=d.kind == value, value)
              ],
            ),
          ]),
        ]),
      ]),
      @html.div(class="capacity-grid", [
        field(
          "capacity-concurrency",
          "Minimum tested concurrency (1–1024)",
          d.minimum_concurrency,
          MinimumConcurrency,
          emit,
        ),
        field(
          "capacity-p95",
          "Maximum p95 latency (ms)",
          d.maximum_p95,
          MaximumP95,
          emit,
        ),
        field(
          "capacity-throughput",
          "Minimum throughput (output units/s)",
          d.minimum_throughput,
          MinimumThroughput,
          emit,
        ),
        field(
          "capacity-failures",
          "Maximum failures (per mille, 0–1000)",
          d.maximum_failures,
          MaximumFailures,
          emit,
        ),
      ]),
      @html.button(
        type_="button",
        on_click=send(emit, Prepare),
        @i18n.copy(
          locale, "Compare and prepare packet", "比较并生成规划包",
        ),
      ),
      @html.button(
        type_="button",
        on_click=send(emit, Reset),
        @i18n.copy(locale, "Clear local draft", "清空本地草稿"),
      ),
      match state.packet {
        None =>
          @html.p(
            "No current planning packet. Editing inputs or selection requires preparing again.",
          )
        Some(packet) =>
          @html.div([
            @html.h3(
              @i18n.copy(locale, "3. Compare and export", "3. 比较并导出"),
            ),
            @html.p(class="capacity-id", packet.packet_id),
            @html.p(
              class="capacity-boundary",
              "Throughput uses the existing sum(output units) / sum(sample durations) statistic, not aggregate fleet throughput. Legacy failure rates round down to whole per mille: 0‰ can include failed samples. The objective and envelope statuses below use exact failed/total counts. Suggested concurrency keeps the legacy rounded-rate heuristic; a lower suggestion was not tested by this run. Meeting the declared objective describes only these samples and is not a future guarantee.",
            ),
            @html.div(class="capacity-table", [
              @html.table([
                @html.caption(
                  "Bounded choices from individual matching runs; no pooling or extrapolation",
                ),
                @html.thead([
                  @html.tr(
                    [
                      for
                        label in [
                          "Run / origin", "Samples", "Tested / suggested concurrency",
                          "p95 ms", "Units/s", "Observed failures / rounded rate",
                          "Memory headroom MiB", "Exact-count objective / envelope",
                        ] => @html.th(label)
                    ],
                  ),
                ]),
                @html.tbody(
                  [
                    for index, choice in packet.choices => {
                      let r = choice.recommendation
                      let evidence = packet.input.evidence[index]
                      let failed = @planning.observed_failure_count(evidence)
                      let objective_met = @planning.observed_objective_met(
                        evidence, r,
                      )
                      @html.tr([
                        @html.td([
                          @html.strong(choice.run_id),
                          @html.p(origin_label(choice.origin)),
                          @html.p(choice.source_ref),
                        ]),
                        @html.td("\{r.summary.sample_count}"),
                        @html.td(
                          "\{choice.tested_concurrency} / \{r.capacity.recommended_concurrency}",
                        ),
                        @html.td("\{r.summary.latency_p95_ms}"),
                        @html.td("\{r.summary.throughput_units_per_second}"),
                        @html.td(
                          "\{failed}/\{r.summary.sample_count} · \{r.summary.failure_per_mille}‰ (rounded down)",
                        ),
                        @html.td("\{r.capacity.memory_headroom_mib}"),
                        @html.td(
                          (if objective_met {
                            "Objective met"
                          } else {
                            "Objective not met"
                          }) +
                          " / " +
                          (if choice.meets_declared_envelope {
                            "Within workload envelope"
                          } else {
                            "Outside workload envelope"
                          }),
                        ),
                      ])
                    }
                  ],
                ),
              ]),
            ]),
            @html.a(
              href="data:application/json;charset=utf-8;base64," +
                @base64.encode(@utf8.encode(packet.export_json())),
              download="lunanexa-capacity-plan.json",
              "Download exact planning packet",
            ),
            try packet.summary_csv() catch {
              error =>
                @html.p(
                  attrs=@html.Attrs::build().role("alert"),
                  "\{Repr(error)}",
                )
            } noraise {
              csv =>
                csv_link(
                  csv, "lunanexa-capacity-summary.csv", "Download comparison summary CSV",
                )
            },
            @html.details([
              @html.summary("Exact packet JSON for inspection / copying"),
              @html.label(
                for_="capacity-export",
                "Exact planning packet JSON (copy to save)",
              ),
              @html.textarea(
                id="capacity-export",
                value=packet.export_json(),
                read_only=true,
                rows=6,
                "",
              ),
            ]),
          ])
      },
      change_view(state, emit),
      @html.h3(
        @i18n.copy(
          locale, "Reopen a saved planning packet", "重新打开已保存的规划包",
        ),
      ),
      @html.p(
        @i18n.copy(
          locale, "Open a saved plan to continue editing.", "打开已保存的规划以继续编辑。",
        ),
      ),
      @html.label(for_="capacity-packet-file", "Saved planning packet file"),
      @html.input(
        id="capacity-packet-file",
        input_type=File,
        accept="application/json,.json",
        on_change=text_emit(emit, _ => ReadFile(true)),
      ),
      @html.details([
        @html.summary("Advanced: paste saved packet JSON"),
        @html.label(for_="capacity-reopen", "Saved planning packet JSON"),
        @html.textarea(
          id="capacity-reopen",
          value=state.reopen_text,
          rows=6,
          maxlength=4194304,
          on_input=text_emit(emit, value => ReopenTextChanged(value)),
          "",
        ),
        @html.button(
          type_="button",
          on_click=send(emit, ReopenPacket),
          @i18n.copy(
            locale, "Verify and reopen packet", "验证并重新打开规划包",
          ),
        ),
      ]),
    ],
  )
}
