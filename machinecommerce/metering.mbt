///|
/// Round cumulative elapsed time, not each polling interval. Differences of
/// these totals telescope so additional polls cannot manufacture usage seconds.
fn cumulative_seconds(elapsed_ms : Int64) -> Int64 {
  elapsed_ms / 1000L + (if elapsed_ms % 1000L == 0L { 0L } else { 1L })
}
