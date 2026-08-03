///|
pub(all) enum RuntimeLifecycle {
  Inspect
  Prepare
  Start
  Ready
  Invoke
  Drain
  Stop
  CollectMetrics
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(open) trait RuntimeAdapter {
  fn name(Self) -> String
  fn inspect(Self, @contracts.RuntimeSpec) -> Bool
  fn invoke(Self, @contracts.WorkloadEnvelope) -> Json raise
}

///|
pub(all) suberror RuntimeError {
  InvalidSpec(String)
  NotReady
  Draining
} derive(Debug, Eq)

///|
pub struct FakeRuntime {
  runtime_name : String
  mut ready : Bool
  mut draining : Bool
  invocations : Array[String]
}

///|
pub fn FakeRuntime::new(name : String) -> FakeRuntime {
  { runtime_name: name, ready: false, draining: false, invocations: [] }
}

///|
pub fn FakeRuntime::start(self : FakeRuntime) -> Unit {
  self.ready = true
  self.draining = false
}

///|
pub fn FakeRuntime::drain(self : FakeRuntime) -> Unit {
  self.draining = true
}

///|
pub fn FakeRuntime::stop(self : FakeRuntime) -> Unit {
  self.ready = false
}

///|
pub fn FakeRuntime::is_ready(self : FakeRuntime) -> Bool {
  self.ready && !self.draining
}

///|
pub fn FakeRuntime::invocation_count(self : FakeRuntime) -> Int {
  self.invocations.length()
}

///|
pub fn FakeRuntime::invoke(
  self : FakeRuntime,
  request : @contracts.WorkloadEnvelope,
) -> Json raise RuntimeError {
  if !self.ready {
    raise NotReady
  }
  if self.draining {
    raise Draining
  }
  self.invocations.push(request.workload_id)
  {
    "kind": "fake.text.chunk",
    "workload_id": request.workload_id,
    "text": "deterministic response",
  }
}

///|
pub impl RuntimeAdapter for FakeRuntime with fn name(self) {
  self.runtime_name
}

///|
pub impl RuntimeAdapter for FakeRuntime with fn inspect(self, spec) {
  spec.name == self.runtime_name &&
  @contracts.valid_sha256_digest(spec.image_digest)
}

///|
pub impl RuntimeAdapter for FakeRuntime with fn invoke(self, request) {
  self.invoke(request)
}
