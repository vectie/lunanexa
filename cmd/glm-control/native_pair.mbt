///|
/// Host-owned deployment configuration; browser actions cannot choose targets.
priv struct NativeTarget {
  host : String
  unit : String
}

///|
fn native_pair_enabled() -> Bool raise {
  match @env.get_env_var("LUNANEXA_GLM_RUNTIME") {
    None | Some("docker") => false
    Some("systemd-user") => true
    _ => raise Failure("unsupported GLM lifecycle runtime")
  }
}

///|
fn native_targets() -> Array[NativeTarget] raise {
  let targets = [
    {
      host: required("LUNANEXA_GLM_HEAD_SSH_TARGET"),
      unit: required("LUNANEXA_GLM_HEAD_UNIT"),
    },
    {
      host: required("LUNANEXA_GLM_WORKER_SSH_TARGET"),
      unit: required("LUNANEXA_GLM_WORKER_UNIT"),
    },
  ]
  for target in targets {
    guard target.unit.has_suffix(".service") &&
      target.unit.all(c => {
        c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '_' | '.')
      }) else {
      raise Failure("invalid native unit")
    }
  }
  targets
}

///|
async fn native_remote(target : NativeTarget, args : Array[String]) -> String {
  let (code, output, _) = @process.collect_output(
    "ssh",
    ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", target.host] + args,
  )
  guard code == 0 && output.text().length() <= 1048576 else {
    raise Failure("native pair target unavailable")
  }
  output.text()
}

///|
fn unit_active(text : String) -> Bool raise {
  guard text.split("\n").contains("LoadState=loaded") else {
    raise Failure("native unit is not installed")
  }
  text.split("\n").contains("ActiveState=active") ||
  text.split("\n").contains("ActiveState=activating") ||
  text.split("\n").contains("ActiveState=deactivating")
}

///|
async fn native_observe() -> Array[Bool] {
  let result = []
  for target in native_targets() {
    result.push(
      unit_active(
        native_remote(target, [
          "systemctl",
          "--user",
          "show",
          target.unit,
          "-p",
          "LoadState",
          "-p",
          "ActiveState",
        ]),
      ),
    )
  }
  result
}

///|
fn native_state(observed : Array[Bool]) -> String {
  if observed.all(x => x) {
    "Running"
  } else if observed.all(x => !x) {
    "Stopped"
  } else {
    "Partial"
  }
}

///|
fn native_stop_order() -> Array[Int32] {
  [0, 1]
}

///|
async fn native_stop() -> String {
  let targets = native_targets()
  // The coordinator owns admission, worker retirement and peer release.
  // Always attempt both stops; one unreachable host must not skip the survivor.
  let mut failed = false
  for rank in native_stop_order() {
    ignore(
      native_remote(targets[rank], [
        "systemctl",
        "--user",
        "stop",
        targets[rank].unit,
      ]),
    ) catch {
      _ => failed = true
    }
  }
  if failed {
    raise Failure("native pair stop incomplete")
  }
  native_state(native_observe())
}

///|
fn mem_available_kib(text : String) -> Int64 raise {
  for line in text.split("\n") {
    if line.has_prefix("MemAvailable:") {
      for part in line.split(" ") {
        if part != "" && part[0] is ('0'..<='9') {
          return @string.parse_int64(part)
        }
      }
    }
  }
  raise Failure("host memory observation unavailable")
}

///|
fn gpu_memory_mib(text : String) -> Int64 raise {
  let mut total = 0L
  for line in text.split("\n") {
    if line.trim() != "" {
      total += @string.parse_int64(line.trim())
    }
  }
  total
}

///|
async fn native_memory_ok(target : NativeTarget) -> Bool {
  let host = mem_available_kib(native_remote(target, ["cat", "/proc/meminfo"]))
  let gpu = gpu_memory_mib(
    native_remote(target, [
      "nvidia-smi", "--query-compute-apps=used_gpu_memory", "--format=csv,noheader,nounits",
    ]),
  )
  host >= 16777216L && gpu <= 102400L
}

///|
async fn native_start() -> String {
  guard native_state(native_observe()) == "Stopped" else {
    raise Failure("native pair is not stopped")
  }
  let targets = native_targets()
  for target in targets {
    guard native_remote(target, [
        "nvidia-smi", "--query-compute-apps=pid", "--format=csv,noheader,nounits",
      ]).trim() ==
      "" &&
      native_memory_ok(target) else {
      raise Failure("Spark pair is not available")
    }
  }
  errdefer @async.protect_from_cancel(() => {
    ignore(native_stop()) catch {
      _ => ()
    }
  })
  for rank in [1, 0] {
    ignore(
      native_remote(targets[rank], [
        "systemctl",
        "--user",
        "start",
        targets[rank].unit,
      ]),
    )
  }
  native_state(native_observe())
}

///|
test "native pair lifecycle and memory envelope" {
  assert_eq(native_stop_order(), [0, 1])
  assert_eq(native_state([true, false]), "Partial")
  assert_eq(native_state([false, false]), "Stopped")
  assert_true(unit_active("LoadState=loaded\nActiveState=deactivating\n"))
  assert_false(unit_active("LoadState=loaded\nActiveState=failed\n"))
  try unit_active("LoadState=not-found\nActiveState=inactive\n") catch {
    _ => ()
  } noraise {
    _ => fail("missing unit cannot be stopped evidence")
  }
  assert_eq(
    mem_available_kib("MemTotal: 127598772 kB\nMemAvailable:   16777216 kB\n"),
    16777216L,
  )
  assert_eq(gpu_memory_mib("97654\n"), 97654L)
  assert_eq(gpu_memory_mib(""), 0L)
}

///|
async fn native_monitor() -> Unit {
  let states = native_observe()
  if states.any(x => x) {
    let mut stop = !states.all(x => x)
    for target in native_targets() {
      if !native_memory_ok(target) {
        stop = true
      }
    }
    if stop {
      println("native GLM pair retired: peer or memory envelope")
      ignore(native_stop())
    }
  }
}
