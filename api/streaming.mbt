///|
pub(all) enum StreamEvent {
  Opened
  Chunk(sequence~ : Int, output~ : Json)
  Usage(@contracts.Usage)
  Completed(receipt~ : String)
  Failed(@contracts.PublicError)
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror StreamError {
  Backpressure
  StreamClosed
} derive(Debug, Eq)

///|
pub struct StreamSession {
  workload_id : String
  capacity : Int
  events : Array[StreamEvent]
  mut closed : Bool
  mut cancelled : Bool
}

///|
pub fn StreamSession::new(
  workload_id : String,
  capacity : Int,
) -> StreamSession {
  {
    workload_id,
    capacity: capacity.max(1),
    events: [Opened],
    closed: false,
    cancelled: false,
  }
}

///|
pub fn StreamSession::workload_id(self : StreamSession) -> String {
  self.workload_id
}

///|
pub fn StreamSession::push(
  self : StreamSession,
  event : StreamEvent,
) -> Unit raise StreamError {
  if self.closed {
    raise StreamClosed
  }
  if self.events.length() >= self.capacity {
    raise Backpressure
  }
  self.events.push(event)
  match event {
    Completed(_) | Failed(_) | Cancelled => self.closed = true
    _ => ()
  }
}

///|
pub fn StreamSession::next(self : StreamSession) -> StreamEvent? {
  if self.events.length() == 0 {
    None
  } else {
    Some(self.events.remove(0))
  }
}

///|
pub fn StreamSession::cancel(self : StreamSession) -> Unit {
  if !self.closed {
    self.cancelled = true
    self.events.push(Cancelled)
    self.closed = true
  }
}

///|
pub fn StreamSession::is_cancelled(self : StreamSession) -> Bool {
  self.cancelled
}

///|
pub(all) struct BatchKey {
  model_selector : String
  capability : @contracts.Capability
  data_class : @contracts.DataClass
  output_format : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn batch_compatible(
  left : @contracts.WorkloadEnvelope,
  right : @contracts.WorkloadEnvelope,
) -> Bool {
  left.model_selector == right.model_selector &&
  left.capability == right.capability &&
  left.data_policy.classification == right.data_policy.classification &&
  left.output_format == right.output_format &&
  left.deadline_unix_ms == right.deadline_unix_ms
}
