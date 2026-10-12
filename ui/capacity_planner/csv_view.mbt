///|
fn csv_field(
  label : String,
  value : String,
  field : CsvField,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  let id = "capacity-csv-" + label.replace(old=" ", new="-")
  @html.div([
    @html.label(for_=id, label),
    @html.input(
      id~,
      value~,
      maxlength=512,
      on_input=text_emit(emit, value => EditCsv(field, value)),
    ),
  ])
}

///|
fn csv_metadata_field(
  label : String,
  value : String,
  field : MetadataField,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  let id = "capacity-csv-" + label.replace(old=" ", new="-")
  @html.div([
    @html.label(for_=id, label),
    @html.input(
      id~,
      value~,
      maxlength=512,
      on_input=text_emit(emit, value => EditCsvMetadata(field, value)),
    ),
  ])
}

///|
fn csv_view(state : State, emit : @rabbita.Emit[Message]?) -> @rabbita.Html {
  let c = state.csv
  let m = c.metadata
  @html.details([
    @html.summary("Import raw benchmark CSV observations"),
    @html.p(
      "One CSV describes one run. Choose or paste comma-separated UTF-8 data with a header and 1–10000 observation rows. Map every metric and declare run context; nothing is uploaded. Only mapped samples and declared context enter the comparison.",
    ),
    @html.label(for_="capacity-csv-file", "Raw benchmark CSV file"),
    @html.input(
      id="capacity-csv-file",
      input_type=File,
      accept="text/csv,.csv",
      on_change=text_emit(emit, _ => ReadCsvFile),
    ),
    @html.details([
      @html.summary("Or paste CSV text"),
      @html.label(for_="capacity-csv-text", "CSV text"),
      @html.textarea(
        id="capacity-csv-text",
        value=c.text,
        rows=5,
        maxlength=4194304,
        on_input=text_emit(emit, value => CsvTextChanged(value)),
        "",
      ),
      @html.button(
        type_="button",
        on_click=send(emit, CsvPreview),
        "Preview CSV columns",
      ),
    ]),
    match c.error {
      Some(error) => @html.p(attrs=@html.Attrs::build().role("alert"), error)
      None => @html.nothing
    },
    match c.notice {
      Some(notice) => @html.p(attrs=@html.Attrs::build().role("status"), notice)
      None => @html.nothing
    },
    match c.preview {
      None =>
        @html.p(
          "Choose a CSV file or preview pasted text to map columns. Your current comparison is retained until Add / replace CSV run succeeds.",
        )
      Some(preview) =>
        @html.div([
          @html.p(
            "\{preview.sample_count} sample records · \{preview.headers.length()} columns. First \{preview.first_rows.length()} records below; every record is validated when adding.",
          ),
          @html.div(class="capacity-table", [
            @html.table([
              @html.caption("CSV preview, before metric conversion"),
              @html.thead([
                @html.tr([ for header in preview.headers => @html.th(header) ]),
              ]),
              @html.tbody(
                [
                  for row in preview.first_rows => {
                    @html.tr([ for cell in row => @html.td(cell) ])
                  }
                ],
              ),
            ]),
          ]),
          @html.h4("Map observed metrics"),
          @html.p(
            "Verify units: latency, queue, load, first output and duration are whole milliseconds; output is whole units; utilization is 0–1000 per mille. Failed accepts true/false or 1/0 (1 means failed). No rounding, missing-value defaults, unit conversion or row dropping. Extra columns are ignored. Exact standard header names are preselected.",
          ),
          @html.div(
            class="capacity-grid",
            [
              for index, metric in csv_metrics() => {
                let id = "capacity-csv-map-" + metric
                @html.div([
                  @html.label(for_=id, metric),
                  @html.select(
                    id~,
                    on_change=text_emit(emit, value => CsvMap(index, value)),
                    [
                      @html.option(
                        value="",
                        selected=c.mappings[index] == "",
                        "Choose CSV column",
                      ),
                    ] +
                    [
                      for header in preview.headers => {
                        @html.option(
                          value=header,
                          selected=c.mappings[index] == header,
                          header,
                        )
                      }
                    ],
                  ),
                ])
              }
            ],
          ),
          @html.h4("Declare this run's identity and provenance"),
          @html.div(class="capacity-grid", [
            csv_field("Run ID", c.run_id, RunId, emit),
            csv_field("Profile", c.profile, Profile, emit),
            csv_field(
              "Model artifact digest",
              c.model_digest,
              ModelDigest,
              emit,
            ),
            csv_field(
              "Runtime image digest",
              c.runtime_digest,
              RuntimeDigest,
              emit,
            ),
            csv_field(
              "Hardware driver and topology profile",
              c.hardware_profile,
              HardwareProfile,
              emit,
            ),
            csv_field("Tested concurrency", c.concurrency, Concurrency, emit),
            @html.div([
              @html.label(for_="capacity-csv-kind", "Benchmark kind"),
              @html.select(
                id="capacity-csv-kind",
                on_change=text_emit(emit, value => EditCsv(Kind, value)),
                [
                  for
                    value in [
                      "Concurrency", "Saturation", "ColdStart", "LongStream", "MixedWorkload",
                    ] => @html.option(value~, selected=c.kind == value, value)
                ],
              ),
            ]),
            @html.div([
              @html.label(
                for_="capacity-csv-origin",
                "Provenance declaration (required)",
              ),
              @html.select(
                id="capacity-csv-origin",
                on_change=text_emit(emit, value => {
                  EditCsvMetadata(Origin, value)
                }),
                [
                  @html.option(
                    value="",
                    selected=m.origin == "",
                    "Choose provenance",
                  ),
                  @html.option(
                    value="SyntheticFixture",
                    selected=m.origin == "SyntheticFixture",
                    "Synthetic fixture · no physical measurement",
                  ),
                  @html.option(
                    value="LocalObservation",
                    selected=m.origin == "LocalObservation",
                    "Local observation · operator-declared, unverified",
                  ),
                ],
              ),
            ]),
            csv_metadata_field(
              "Source record reference",
              m.source_ref,
              SourceRef,
              emit,
            ),
            csv_metadata_field(
              "Exact workload revision",
              m.workload_ref,
              WorkloadRef,
              emit,
            ),
            csv_metadata_field("Output unit", m.output_unit, OutputUnit, emit),
            csv_metadata_field(
              "Measured total memory MiB",
              m.memory_total,
              MemoryTotal,
              emit,
            ),
            csv_metadata_field(
              "Measured peak memory MiB",
              m.memory_peak,
              MemoryPeak,
              emit,
            ),
          ]),
          @html.p(
            "Enter memory from the same run and pool. Import does not authenticate measurements or qualify a physical cluster. Adding an existing Run ID replaces only that run; other comparison sources remain. New sources are selected automatically.",
          ),
          @html.button(
            type_="button",
            on_click=send(emit, AddCsv),
            "Add / replace CSV run",
          ),
        ])
    },
    @html.button(
      type_="button",
      on_click=send(emit, ClearCsv),
      "Clear CSV staging",
    ),
    match c.mapping_json {
      Some(json) =>
        @html.a(
          href="data:application/json;charset=utf-8;base64," +
            @base64.encode(@utf8.encode(json)),
          download="lunanexa-csv-mapping.json",
          "Download CSV import mapping JSON",
        )
      None => @html.nothing
    },
  ])
}
