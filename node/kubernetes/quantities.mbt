///|
/// Render the API server's canonical quantity spelling before journaling the
/// immutable intent. Otherwise 1000m -> 1 is mistaken for resource tampering.
fn canonical_cpu_quantity(millis : Int) -> String {
  if millis % 1000 == 0 {
    (millis / 1000).to_string()
  } else {
    millis.to_string() + "m"
  }
}

///|
/// Input is positive whole MiB, already bounded by the assignment validator.
/// Divide before formatting; never multiply into an overflowing Int byte count.
fn canonical_memory_quantity(mib : Int) -> String {
  for unit in [(1073741824, "Pi"), (1048576, "Ti"), (1024, "Gi")] {
    let (scale, suffix) = unit
    if mib % scale == 0 {
      return (mib / scale).to_string() + suffix
    }
  }
  mib.to_string() + "Mi"
}
