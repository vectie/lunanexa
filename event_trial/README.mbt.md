# Event admission and bounded routing

The account store owns durable event policies and trial participants. This
package contains the portable contract and process-local in-flight chooser.
It does not allocate nodes, grant credentials or probe readiness.

```mbt check
///|
test "reserve only an eligible node" {
  let router = @event_trial.Router::new()
  let nodes = ["replica-a", "replica-b", "replica-c", "replica-d"]
  assert_eq(router.reserve("call-a", nodes, 1), Some("replica-a"))
  assert_eq(router.reserve("call-b", nodes, 1), Some("replica-b"))
  router.release("call-a")
  assert_eq(router.reserve("call-a", ["replica-a"], 1), Some("replica-a"))
}
```
