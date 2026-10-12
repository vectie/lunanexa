///|
pub(all) struct Explorer {
  run_id : String
  failed_only : Bool
  order : @planning.SampleOrder
  page : Int
  export_csv : String?
} derive(Eq)

///|
pub extend Explorer with Eq::{equal, not_equal}

///|
fn empty_explorer() -> Explorer {
  {
    run_id: "",
    failed_only: false,
    order: RecordedOrder,
    page: 0,
    export_csv: None,
  }
}

///|
fn update_explorer(state : State, message : Message) -> State {
  let e = state.explorer
  let next = match message {
    ExploreRun(id) => {
      if !state.sources.any(source => source.run.run_id == id) {
        return state
      }
      { ..empty_explorer(), run_id: id, }
    }
    ExploreFailures(failed_only) =>
      { ..e, failed_only, page: 0, export_csv: None, }
    ExploreOrder(order) => { ..e, order, page: 0, export_csv: None, }
    ExplorePage(page) => { ..e, page: page.max(0).min(399), }
    ExportSamples => {
      guard state.sources
        .iter()
        .find_first(source => source.run.run_id == e.run_id)
        is Some(source) else {
        return state
      }
      try @planning.samples_csv(source, e.failed_only, e.order) catch {
        error => return { ..state, error: Some("\{Repr(error)}"), }
      } noraise {
        csv => { ..e, export_csv: Some(csv), }
      }
    }
    _ => e
  }
  { ..state, explorer: next, }
}

///|
fn csv_link(text : String, filename : String, label : String) -> @rabbita.Html {
  @html.a(
    href="data:text/csv;charset=utf-8;base64," +
      @base64.encode(@utf8.encode(text)),
    download=filename,
    label,
  )
}

///|
fn explorer_view(
  state : State,
  emit : @rabbita.Emit[Message]?,
) -> @rabbita.Html {
  let e = state.explorer
  guard state.sources.iter().find_first(source => source.run.run_id == e.run_id)
    is Some(source) else {
    return @html.p(
      "Choose Inspect samples on a captured run to explore its observations.",
    )
  }
  let rows = @planning.explore_samples(source, e.failed_only, e.order) catch {
    error =>
      return @html.p(attrs=@html.Attrs::build().role("alert"), "\{Repr(error)}")
  }
  let page = e.page.min((rows.length() - 1).max(0) / 25)
  let start = page * 25
  let end = (start + 25).min(rows.length())
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("sample-explorer-title"),
    [
      @html.h3(id="sample-explorer-title", "Explore captured samples"),
      @html.p(
        "Run: " + source.run.run_id + " · " + origin_label(source.origin),
      ),
      @html.p(
        "Inspect slow requests or failures without changing the full-run comparison. Sample numbers are the original one-based positions. Ties keep recorded order; no samples are pooled. These filters never change objective results.",
      ),
      @html.label(for_="sample-filter", "Sample filter"),
      @html.select(
        id="sample-filter",
        on_change=text_emit(emit, value => ExploreFailures(value == "failed")),
        [
          @html.option(value="all", selected=!e.failed_only, "All samples"),
          @html.option(
            value="failed",
            selected=e.failed_only,
            "Failed samples only",
          ),
        ],
      ),
      @html.label(for_="sample-order", "Sample order"),
      @html.select(
        id="sample-order",
        on_change=text_emit(emit, value => {
          ExploreOrder(
            match value {
              "latency" => SlowestLatency
              "queue" => LongestQueue
              _ => RecordedOrder
            },
          )
        }),
        [
          @html.option(
            value="recorded",
            selected=e.order == RecordedOrder,
            "Recorded order",
          ),
          @html.option(
            value="latency",
            selected=e.order == SlowestLatency,
            "Slowest latency first",
          ),
          @html.option(
            value="queue",
            selected=e.order == LongestQueue,
            "Longest queue first",
          ),
        ],
      ),
      @html.p(
        attrs=@html.Attrs::build().role("status"),
        if rows.is_empty() {
          "No samples match this filter. The complete run still contains \{source.run.samples.length()} samples."
        } else {
          "Showing \{start + 1}–\{end} of \{rows.length()} matching samples (\{source.run.samples.length()} in the complete run)."
        },
      ),
      @html.div(class="capacity-table", [
        @html.table([
          @html.caption(
            "Individual measurements · output unit: " + source.output_unit,
          ),
          @html.thead([
            @html.tr(
              [
                for
                  label in [
                    "Sample #", "Latency ms", "Queue ms", "Load ms", "First output ms",
                    "Output units", "Duration ms", "Utilization ‰", "Failed",
                  ] => @html.th(label)
              ],
            ),
          ]),
          @html.tbody(
            [
              for row in rows[start:end] => {
                let s = row.sample
                @html.tr(
                  [
                    for
                      value in [
                        "\{row.sample_index}",
                        "\{s.latency_ms}",
                        "\{s.queue_ms}",
                        "\{s.load_ms}",
                        "\{s.first_output_ms}",
                        "\{s.output_units}",
                        "\{s.duration_ms}",
                        "\{s.utilization_per_mille}",
                        "\{s.failed}",
                      ] => @html.td(value)
                  ],
                )
              }
            ],
          ),
        ]),
      ]),
      @html.button(
        type_="button",
        disabled=page == 0,
        on_click=send(emit, ExplorePage(page - 1)),
        "Previous samples",
      ),
      @html.button(
        type_="button",
        disabled=end >= rows.length(),
        on_click=send(emit, ExplorePage(page + 1)),
        "Next samples",
      ),
      @html.button(
        type_="button",
        on_click=send(emit, ExportSamples),
        "Prepare matching samples CSV",
      ),
      match e.export_csv {
        Some(csv) =>
          csv_link(
            csv, "lunanexa-benchmark-samples.csv", "Download all matching samples CSV",
          )
        None => @html.nothing
      },
      @html.p(
        "CSV contains every matching row, including those on other pages, with the canonical observation hash. Spreadsheet formula-like text is prefixed with an apostrophe; the exact JSON remains the authoritative artifact.",
      ),
    ],
  )
}
