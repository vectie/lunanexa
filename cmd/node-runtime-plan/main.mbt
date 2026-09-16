///|
priv struct Input {
  settings : @kubernetes.RuntimeSettings
  assignment : @contracts.DesiredAssignment
  artifact_path : String
  verified_digest : String
  verified_size : Int64
  now_unix_ms : Int64
} derive(FromJson)

///|
/// Diagnostic renderer only: performs no signature verification, file digest
/// verification, Kubernetes mutations or hardware inventory claims. The real
/// node supervisor must perform those checks before using the renderer.
async fn main {
  let arguments = @env.args()
  if arguments.length() != 2 {
    fail("usage: node-runtime-plan INPUT.json (render only; no deployment)")
  }
  let file = @fs.open(arguments[1], mode=ReadOnly)
  defer file.close()
  let buffer = Buffer()
  let mut size = 0
  while file.read_some(max_len=8192) is Some(bytes) {
    size += bytes.length()
    if size > 4194304 {
      fail("input exceeds plan limit")
    }
    buffer.write_bytes(bytes)
  }
  let input : Input = @json.from_json(
    @json.parse(@utf8.decode(buffer.to_bytes())),
  )
  let plan = @kubernetes.render_runtime(
    input.settings,
    input.assignment,
    input.artifact_path,
    input.verified_digest,
    input.verified_size,
    input.now_unix_ms,
  )
  let items = [plan.network_policy]
  if plan.claim_template is Some(resource) {
    items.push(resource)
  }
  items.push(plan.pod)
  let result : Json = {
    "apiVersion": "v1",
    "kind": "List",
    "items": items.to_json(),
  }
  println(result.stringify())
}
