///|
extern "js" fn capacity_named_file_text(id : String) -> @js.Promise =
  #|(id) => {
  #|  const input = document.getElementById(id);
  #|  const file = input && input.files && input.files[0];
  #|  if (!file) return Promise.reject(new Error('Choose a file first'));
  #|  input.value = ''; // The same file can be chosen again after an error/edit.
  #|  if (file.size > 16777216) return Promise.reject(new Error('File exceeds the 16 MiB byte limit'));
  #|  return file.arrayBuffer().then(bytes => {
  #|    const text = new TextDecoder('utf-8', {fatal:true}).decode(bytes);
  #|    if (text.length > 4194304) throw new Error('File exceeds the 4 Mi-character limit');
  #|    return text;
  #|  });
  #|}

///|
fn capacity_file_text(reopen : Bool) -> @js.Promise {
  capacity_named_file_text(
    if reopen {
      "capacity-packet-file"
    } else {
      "capacity-evidence-file"
    },
  )
}

///|
fn capacity_planner_command(
  model : AppModel,
  state : @capacity_planner.State,
  message : @capacity_planner.Message,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let send = emit.map(message => Console(CapacityPlanner(message)))
  match message {
    ReadCsvFile => {
      let promise = capacity_named_file_text("capacity-csv-file")
      @rabbita.perform(message => send(message), async fn() noraise {
        let result = Ok(promise.wait().cast()) catch {
          _ =>
            Err(
              "Could not read CSV: choose UTF-8 up to 4 Mi characters (16 MiB byte limit). Current draft retained.",
            )
        }
        CsvFileRead(state.revision, result)
      })
    }
    RefreshRecorded => {
      if !state.refreshing {
        return @rabbita.none
      }
      let sequence = state.refresh_sequence
      @rabbita.perform(outcome => emit(Outcome(outcome)), async fn() noraise {
        let result = try {
          if model.demo_mode || !model.console.operator_authenticated {
            fail(
              "Connect an authenticated operator console to read recorded runs",
            )
          }
          let response = request(
            "GET",
            model.endpoint,
            "/v1/telemetry",
            model.credential,
          )
          Ok(@capacity_planner.decode_telemetry(parse_console_json(response)))
        } catch {
          _ =>
            Err(
              "Recorded benchmark refresh failed. Previous observations, metadata and packet are retained; check operator access and retry.",
            )
        }
        RecordedBenchmarksLoaded(
          model.endpoint,
          model.credential,
          model.cluster_poll_generation,
          sequence,
          result,
        )
      })
    }
    ReadFile(reopen) => {
      // Capture the chosen File synchronously; a later selection cannot change
      // this read. The reducer fences completion against every later edit/read.
      let promise = capacity_file_text(reopen)
      @rabbita.perform(message => send(message), async fn() noraise {
        let result = Ok(promise.wait().cast()) catch {
          _ =>
            Err(
              "Could not read file: choose a UTF-8 JSON file up to 4 Mi characters (16 MiB byte limit). Current draft retained.",
            )
        }
        FileRead(state.revision, reopen, result)
      })
    }
    _ => @rabbita.none
  }
}
