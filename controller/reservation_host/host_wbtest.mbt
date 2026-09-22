///|
struct Fixture {
  mut node : Json
  mut pods : Array[Json]
  mut conflict : Bool
  patches : Array[Json]
}

///|
fn fixture() -> Fixture {
  {
    node: {
      "metadata": { "name": "spark-a", "resourceVersion": "10" },
      "spec": {
        "taints": [
          {
            "key": "maintenance",
            "value": "keep",
            "effect": "PreferNoSchedule",
          },
        ],
      },
    },
    pods: [],
    conflict: false,
    patches: [],
  }
}

///|
fn Fixture::host(self : Fixture) -> ReservationHost raise {
  ReservationHost::new(
    (verb, path, body) => {
      if verb == "PATCH" {
        if self.conflict {
          return (409, Json::null())
        }
        guard body is Some(Array(operations)) &&
          operations.length() == 2 &&
          operations[0]
          is {
            "op": String("test"),
            "path": String("/metadata/resourceVersion"),
            "value": String("10"),
            ..
          } &&
          operations[1]
          is {
            "op": String("add"),
            "path": String("/spec/taints"),
            "value": Array(taints),
            ..
          } else {
          fail("patch missing resourceVersion or taint preservation")
        }
        self.patches.push(body.unwrap())
        self.node = {
          "metadata": { "name": "spark-a", "resourceVersion": "10" },
          "spec": { "taints": taints.to_json() },
        }
        return (200, self.node)
      }
      if path.has_prefix("/api/v1/pods?") {
        (200, { "items": self.pods.to_json() })
      } else {
        (200, self.node)
      }
    },
    "workspaces",
    [
      {
        namespace_name: "monitoring",
        service_account: "node-exporter",
        label_key: "app",
        label_value: "node-exporter",
      },
    ],
  )
}

///|
fn pod(
  namespace_name : String,
  labels : Json,
  service_account : String,
  phase : String,
) -> Json {
  {
    "metadata": { "namespace": namespace_name, "labels": labels },
    "spec": { "nodeName": "spark-a", "serviceAccountName": service_account },
    "status": { "phase": phase },
  }
}

///|
async test "reservation preserves unrelated taints and releases only after workloads stop" {
  let fixture = fixture()
  let host = fixture.host()
  fixture.pods = [
    pod("monitoring", { "app": "node-exporter" }, "node-exporter", "Running"),
  ]
  assert_eq(host.reserve("spark-a", "reservation-a"), Exclusive)
  assert_eq(fixture.patches.length(), 1)
  assert_eq(host.reserve("spark-a", "reservation-a"), Exclusive)
  assert_eq(fixture.patches.length(), 1)
  fixture.pods.push(
    pod(
      "workspaces",
      { "lunanexa.io/reservation": "reservation-a" },
      "tenant",
      "Running",
    ),
  )
  assert_eq(host.reserve("spark-a", "reservation-a"), Exclusive)
  try host.release("spark-a", "reservation-a") catch {
    ReservationHostError::NodeOccupied => ()
    error => raise error
  } noraise {
    _ => fail("running customer pod released")
  }
  ignore(fixture.pods.pop())
  assert_eq(host.release("spark-a", "reservation-a"), Released)
  assert_eq(fixture.node, {
    "metadata": { "name": "spark-a", "resourceVersion": "10" },
    "spec": {
      "taints": [
        { "key": "maintenance", "value": "keep", "effect": "PreferNoSchedule" },
      ],
    },
  })
}

///|
async test "foreign pods including kube-system and incorrect infrastructure identities block reservation" {
  for
    candidate in [
      pod("kube-system", { "app": "benchmark" }, "default", "Running"),
      pod("monitoring", { "app": "node-exporter" }, "wrong-account", "Running"),
      pod(
        "workspaces",
        { "lunanexa.io/reservation": "other" },
        "tenant",
        "Pending",
      ),
    ] {
    let fixture = fixture()
    fixture.pods = [candidate]
    try fixture.host().reserve("spark-a", "reservation-a") catch {
      ReservationHostError::NodeOccupied => ()
      error => raise error
    } noraise {
      _ => fail("foreign pod admitted")
    }
    assert_eq(fixture.patches.length(), 0)
  }
}

///|
async test "resource version conflict never reports exclusive and another owner cannot release" {
  let fixture = fixture()
  fixture.conflict = true
  try fixture.host().reserve("spark-a", "reservation-a") catch {
    ReservationHostError::ReservationConflict => ()
    error => raise error
  } noraise {
    _ => fail("stale patch accepted")
  }
  fixture.conflict = false
  ignore(fixture.host().reserve("spark-a", "reservation-a"))
  try fixture.host().release("spark-a", "reservation-b") catch {
    ReservationHostError::ReservationConflict => ()
    error => raise error
  } noraise {
    _ => fail("foreign reservation released")
  }
}
