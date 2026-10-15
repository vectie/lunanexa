///|
pub(all) struct ChangeState {
  run_id : String
  baseline_packet : @planning.Packet?
  baseline_run_id : String
  report : @planning.ChangeReport?
  error : String?
} derive(Eq)

///|
pub extend ChangeState with Eq::{equal, not_equal}

///|
fn empty_change_state() -> ChangeState {
  {
    run_id: "",
    baseline_packet: None,
    baseline_run_id: "",
    report: None,
    error: None,
  }
}

///|
fn current_change_run(state : State) -> String {
  match state.packet {
    Some(packet) => {
      let selected = state.change_analysis.run_id
      if packet.input.evidence.any(e => e.run.run_id == selected) {
        selected
      } else {
        packet.input.evidence[0].run.run_id
      }
    }
    None => ""
  }
}

///|
fn update_change(state : State, message : Message) -> State {
  let change = state.change_analysis
  let next = match message {
    ChangeClear => empty_change_state()
    ChangeSelectRun(run_id) => { ..change, run_id, report: None, error: None, }
    ChangeCaptureBaseline =>
      match state.packet {
        None =>
          {
            ..change,
            error: Some(
              "Prepare or reopen a packet before capturing a baseline",
            ),
          }
        Some(packet) =>
          try @planning.reopen(packet.export_json()) catch {
            error => { ..change, error: Some("\{Repr(error)}"), }
          } noraise {
            verified =>
              {
                ..change,
                baseline_packet: Some(verified),
                baseline_run_id: current_change_run(state),
                report: None,
                error: None,
              }
          }
      }
    ChangeCompare =>
      match (change.baseline_packet, state.packet) {
        (Some(baseline), Some(candidate)) =>
          try
            @planning.compare_packet_runs(
              baseline,
              change.baseline_run_id,
              candidate,
              current_change_run(state),
            )
          catch {
            error => { ..change, report: None, error: Some("\{Repr(error)}"), }
          } noraise {
            report => { ..change, report: Some(report), error: None, }
          }
        _ =>
          {
            ..change,
            report: None,
            error: Some(
              "Capture a baseline, then prepare or reopen a candidate packet",
            ),
          }
      }
    _ => change
  }
  { ..state, change_analysis: next, }
}

///|
fn change_view(state : State, emit : @rabbita.Emit[Message]?) -> @rabbita.Html {
  let change = state.change_analysis
  @html.section([
    @html.h3("Compare a baseline with a candidate"),
    @html.p(
      "Capture a baseline, then select a candidate. Both use the baseline objective.",
    ),
    match change.error {
      Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
      None => @html.nothing
    },
    match state.packet {
      None =>
        @html.p("Prepare or reopen a packet to choose a run for analysis.")
      Some(packet) =>
        @html.div([
          @html.label(
            for_="capacity-change-run",
            "Run from the current verified packet",
          ),
          @html.select(
            id="capacity-change-run",
            on_change=text_emit(emit, id => ChangeSelectRun(id)),
            [
              for evidence in packet.input.evidence => {
                @html.option(
                  value=evidence.run.run_id,
                  selected=current_change_run(state) == evidence.run.run_id,
                  evidence.run.run_id,
                )
              }
            ],
          ),
          @html.button(
            type_="button",
            on_click=send(emit, ChangeCaptureBaseline),
            "Capture selected run as baseline",
          ),
          @html.button(
            type_="button",
            disabled=change.baseline_packet is None,
            on_click=send(emit, ChangeCompare),
            "Analyze selected candidate against baseline",
          ),
        ])
    },
    match change.baseline_packet {
      None => @html.p("No captured baseline.")
      Some(packet) =>
        @html.div([
          @html.p("Captured baseline: \{change.baseline_run_id}"),
          @html.p(class="capacity-id", packet.packet_id),
          @html.p(
            "Fixed objective: p95 <= \{packet.input.objective.maximum_p95_ms} ms; throughput >= \{packet.input.objective.minimum_throughput_units_per_second} units/s; failures <= \{packet.input.objective.maximum_failure_per_mille} per mille; minimum concurrency \{packet.input.workload.minimum_tested_concurrency}.",
          ),
          @html.button(
            type_="button",
            on_click=send(emit, ChangeClear),
            "Clear baseline and analysis",
          ),
        ])
    },
    match change.report {
      None => @html.nothing
      Some(report) =>
        @html.div([
          @html.h4("Measured baseline-to-candidate changes"),
          @html.p(origin_label(report.input.baseline.origin)),
          @html.p(
            "\{report.input.baseline.run.run_id} → \{report.input.candidate.run.run_id}. Samples: \{report.baseline_summary.sample_count} → \{report.candidate_summary.sample_count}. Exact failure counts: \{report.baseline_failures} → \{report.candidate_failures}; failure rate \{report.failure_rate_direction}.",
          ),
          @html.p(
            "Fixed objective met: baseline \{report.baseline_meets_objective}, candidate \{report.candidate_meets_objective}. Objective plus concurrency envelope: baseline \{report.baseline_meets_envelope}, candidate \{report.candidate_meets_envelope}.",
          ),
          @html.details([
            @html.summary("Both observations and source context"),
            @html.p(
              "Workload: \{report.input.baseline.workload_ref}; profile \{report.input.baseline.run.profile}; kind \{Repr(report.input.baseline.run.kind)}; output unit \{report.input.baseline.output_unit}",
            ),
            @html.p(
              "Baseline: model \{report.input.baseline.run.model_digest}; runtime \{report.input.baseline.run.runtime_digest}; hardware \{report.input.baseline.run.hardware_profile}; source \{report.input.baseline.source_ref}",
            ),
            @html.p(
              "Candidate: model \{report.input.candidate.run.model_digest}; runtime \{report.input.candidate.run.runtime_digest}; hardware \{report.input.candidate.run.hardware_profile}; source \{report.input.candidate.source_ref}",
            ),
          ]),
          @html.h4("Changed configuration"),
          if report.configuration_changes.is_empty() {
            @html.p(
              "No model, runtime, hardware, concurrency or total-memory changes.",
            )
          } else {
            @html.ul(
              [
                for change in report.configuration_changes => {
                  @html.li(
                    "\{change.field}: \{change.baseline} → \{change.candidate}",
                  )
                }
              ],
            )
          },
          @html.div(class="capacity-table", [
            @html.table([
              @html.caption(
                "Candidate minus baseline; individual independent runs, no pooled samples",
              ),
              @html.thead([
                @html.tr(
                  [
                    for
                      label in [
                        "Metric", "Baseline", "Candidate", "Delta", "Relative delta",
                      ] => @html.th(label)
                  ],
                ),
              ]),
              @html.tbody(
                [
                  for metric in report.metrics => {
                    @html.tr([
                      @html.td(metric.metric + " (" + metric.unit + ")"),
                      @html.td(metric.baseline.to_string()),
                      @html.td(metric.candidate.to_string()),
                      @html.td(metric.delta.to_string()),
                      @html.td(
                        match metric.relative_per_mille {
                          Some(n) => "\{n}‰ of baseline"
                          None => "Unavailable (zero baseline)"
                        },
                      ),
                    ])
                  }
                ],
              ),
            ]),
          ]),
          @html.p(
            class="capacity-boundary",
            "Relative changes are truncated toward zero. Failure-rate direction uses exact failed/total ratios, even when rounded rates are zero. Different configurations and sample counts can confound this comparison. No significance, causal attribution, output-quality comparison, automatic winner, deployment or future guarantee is implied. Throughput is sum(output units) / sum(sample durations), not fleet throughput.",
          ),
          @html.a(
            href="data:application/json;charset=utf-8;base64," +
              @base64.encode(@utf8.encode(report.export_json())),
            download="lunanexa-benchmark-change.json",
            "Download reproducible change analysis JSON",
          ),
          @html.a(
            href="data:text/plain;charset=utf-8;base64," +
              @base64.encode(@utf8.encode(report.summary_text())),
            download="lunanexa-benchmark-change.txt",
            "Download readable change report",
          ),
        ])
    },
  ])
}
