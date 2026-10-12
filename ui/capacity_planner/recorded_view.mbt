///|
fn metadata_field(
  id : String,
  label : String,
  value : String,
  field : MetadataField,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  @html.div([
    @html.label(for_=id, label),
    @html.input(
      id~,
      value~,
      maxlength=320,
      on_input=text_emit(emit, value => EditMetadata(field, value)),
    ),
  ])
}

///|
fn recorded_view(
  state : State,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  @html.div([
    @html.h3("1. Select recorded run"),
    @html.p(
      "Reads exact samples from this operator console’s telemetry history. Recording a run does not establish its provenance, workload, output unit or measured memory; declare the missing context below.",
    ),
    @html.button(
      type_="button",
      on_click=send(emit, RefreshRecorded),
      if state.refreshing {
        "Refreshing recorded runs…"
      } else {
        "Refresh recorded runs"
      },
    ),
    match state.refresh_error {
      Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
      None => @html.nothing
    },
    if state.recorded_runs.is_empty() {
      @html.p(
        if state.recorded_loaded {
          "No recorded benchmark runs in this snapshot. Record a benchmark first, or import a complete producer evidence file."
        } else {
          "Recorded benchmarks have not loaded. Connect the operator console and refresh, or import a producer evidence file."
        },
      )
    } else {
      @html.nothing
    },
    @html.div(
      [
        for run in state.recorded_runs => {
          @html.article(class="capacity-run", [
            @html.strong(run.run_id),
            @html.p(
              "\{run.profile} · \{Repr(run.kind)} · concurrency \{run.concurrency} · \{run.samples.length()} raw samples",
            ),
            @html.details([
              @html.summary(
                "Model, runtime, hardware and exact observation identity",
              ),
              @html.p("Model: \{run.model_digest}"),
              @html.p("Runtime: \{run.runtime_digest}"),
              @html.p("Hardware: \{run.hardware_profile}"),
              @html.p("Raw run SHA-256: \{@planning.observation_digest(run)}"),
              @html.p(
                "Observed benchmark snapshot SHA-256: \{state.recorded_snapshot}",
              ),
            ]),
            @html.button(
              type_="button",
              on_click=send(emit, SelectRecorded(run.run_id)),
              "Select recorded run",
            ),
          ])
        }
      ],
    ),
    match state.pending_recording {
      None => @html.nothing
      Some(recording) => {
        let d = recording.metadata
        @html.article(class="capacity-run", [
          @html.h3("Complete missing context for \{recording.run.run_id}"),
          if recording_changed(state, recording) {
            @html.p(
              attrs=@html.Attrs::build().role("alert"),
              "This captured run changed or disappeared on refresh. Your fields are retained. Cancel and select the current run to continue.",
            )
          } else {
            @html.nothing
          },
          @html.label(
            for_="capacity-origin",
            "Provenance declaration (required)",
          ),
          @html.select(
            id="capacity-origin",
            on_change=text_emit(emit, value => EditMetadata(Origin, value)),
            [
              @html.option(
                value="",
                selected=d.origin == "",
                "Choose provenance; unknown is not accepted",
              ),
              @html.option(
                value="SyntheticFixture",
                selected=d.origin == "SyntheticFixture",
                "Synthetic fixture · no physical measurement",
              ),
              @html.option(
                value="LocalObservation",
                selected=d.origin == "LocalObservation",
                "Local observation · operator-declared, unverified",
              ),
            ],
          ),
          @html.div(class="capacity-grid", [
            metadata_field(
              "capacity-source-ref",
              "Source / measurement record reference",
              d.source_ref,
              SourceRef,
              emit,
            ),
            metadata_field(
              "capacity-record-workload",
              "Exact workload / dataset revision reference",
              d.workload_ref,
              WorkloadRef,
              emit,
            ),
            metadata_field(
              "capacity-record-unit",
              "Output unit (for example, tokens)",
              d.output_unit,
              OutputUnit,
              emit,
            ),
            metadata_field(
              "capacity-memory-total",
              "Measured total memory (MiB)",
              d.memory_total,
              MemoryTotal,
              emit,
            ),
            metadata_field(
              "capacity-memory-peak",
              "Measured peak memory for this run (MiB)",
              d.memory_peak,
              MemoryPeak,
              emit,
            ),
          ]),
          @html.p(
            "Enter measurements from the same run and memory pool. No memory value is inferred from current node counters. Use separate packets for synthetic fixtures and local observations.",
          ),
          @html.button(
            type_="button",
            on_click=send(emit, AddRecorded),
            "Add / update run in comparison",
          ),
          @html.button(
            type_="button",
            on_click=send(emit, CancelRecorded),
            "Cancel selection",
          ),
        ])
      }
    },
    @html.details([
      @html.summary("Or import a complete producer evidence file"),
      @html.p(
        "Choose a UTF-8 evidence JSON file, up to 4 Mi characters and 8 runs (16 MiB byte limit). The native benchmark-evidence exporter writes this format. Imported metadata and samples are validated together; no JSON editing is needed.",
      ),
      @html.label(for_="capacity-evidence-file", "Benchmark evidence file"),
      @html.input(
        id="capacity-evidence-file",
        input_type=File,
        accept="application/json,.json",
        on_change=text_emit(emit, _ => ReadFile(false)),
      ),
    ]),
    if state.reading_file {
      @html.p("Reading selected file…")
    } else {
      @html.nothing
    },
  ])
}
