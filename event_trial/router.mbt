///|
/// Process-local in-flight reservations. Durable scheduler admission owns
/// reconstruction-time duplicate rejection; no request is relaunched here.
pub struct Router {
  active : Map[String, String]
  mut cursor : Int32
  affinity : Map[String, (String, Int64)]
}

///|
pub fn Router::new() -> Router {
  { active: Map([]), cursor: 0, affinity: Map([]), }
}

///|
/// Atomically reserves the least-loaded eligible replica. The chosen stream
/// stays pinned. Zero means no event-specific concurrency cap; a positive
/// operator limit rejects full pools without adding another queue. Durable
/// infrastructure admission and the serving runtime retain their own budgets.
pub fn Router::reserve(
  self : Router,
  workload_id : String,
  candidates : Array[String],
  maximum : Int32,
  prefix~ : String = "",
  now~ : Int64 = 0L,
) -> String? {
  if self.active.contains(workload_id) || candidates.is_empty() || maximum < 0 {
    return None
  }
  let mut chosen : String? = None
  let mut minimum = 0
  for offset in 0..<candidates.length() {
    let node = candidates[(self.cursor + offset) % candidates.length()]
    let count = self.active.values().filter(v => v == node).count()
    if (maximum == 0 || count < maximum) && (chosen is None || count < minimum) {
      minimum = count
      chosen = Some(node)
    }
  }
  if chosen is Some(node) {
    // Soft affinity is only a prediction, never a claim of a runtime cache hit.
    // A busy preferred replica falls back to least-load without rejecting or
    // queuing the request. At most one extra in-flight stream gets the tie.
    let preferred = if prefix != "" {
      match self.affinity.get(prefix) {
        Some((prior, seen)) if now >= seen &&
          now - seen < 300000L &&
          candidates.contains(prior) => {
          let count = self.active.values().filter(v => v == prior).count()
          if count <= minimum + 1 && (maximum == 0 || count < maximum) {
            prior
          } else {
            node
          }
        }
        _ => node
      }
    } else {
      node
    }
    self.active[workload_id] = preferred
    if prefix != "" {
      if self.affinity.length() >= 4096 {
        self.affinity.clear()
      }
      self.affinity[prefix] = (preferred, now)
    }
    self.cursor = (self.cursor + 1) % candidates.length()
    return Some(preferred)
  }
  chosen
}

///|
pub fn Router::release(self : Router, workload_id : String) -> Unit {
  ignore(self.active.remove(workload_id))
}

///|
/// Used only to avoid interrupting a live stream when releasing a model node.
pub fn Router::in_flight(self : Router, node_id : String) -> Int32 {
  self.active.values().filter(v => v == node_id).count()
}
