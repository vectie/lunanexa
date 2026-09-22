///|
/// Production document execution runs in a tokenless, network-isolated pod.
/// Dispatcher tokens never enter this manifest; only the rendering authority is
/// scoped into the two containers that must produce/verify render evidence.
fn artifact_job_manifest(
  name : String,
  job_namespace : String,
  image : String,
  subpath : String,
  state_claim : String,
  font_claim : String,
  render_secret : String,
  binding : String,
) -> Json {
  let common_env : Array[Json] = [
    { "name": "LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT", "value": "/job" },
    { "name": "LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME", "value": "job.json" },
    { "name": "LUNANEXA_OFFLINE_FONT_ROOT", "value": "/fonts" },
    {
      "name": "LUNANEXA_OFFLINE_FONT_CONFIG_FILENAME",
      "value": "/fonts/manifest.json",
    },
  ]
  let evidence_env : Json = {
    "name": "LUNANEXA_RENDER_EVIDENCE_SECRET",
    "valueFrom": {
      "secretKeyRef": {
        "name": render_secret,
        "key": "LUNANEXA_RENDER_EVIDENCE_SECRET",
      },
    },
  }
  let mounts : Json = [
    { "name": "work", "mountPath": "/job", "subPath": subpath },
    { "name": "fonts", "mountPath": "/fonts", "readOnly": true },
    { "name": "tmp", "mountPath": "/tmp" },
  ]
  let security : Json = {
    "allowPrivilegeEscalation": false,
    "readOnlyRootFilesystem": true,
    "capabilities": { "drop": ["ALL"] },
  }
  fn container(
    label : String,
    binary : String,
    mode : String,
    signed : Bool,
  ) -> Json {
    let variables = common_env.copy()
    variables.push({ "name": "LUNANEXA_OFFLINE_ARTIFACT_MODE", "value": mode })
    if signed {
      variables.push(evidence_env)
    }
    {
      "name": label,
      "image": image,
      "imagePullPolicy": "IfNotPresent",
      "command": [binary],
      "env": variables.to_json(),
      "volumeMounts": mounts,
      "securityContext": security,
      "resources": {
        "requests": { "cpu": "100m", "memory": "128Mi" },
        "limits": { "cpu": "2", "memory": "2Gi" },
      },
    }
  }
  {
    "apiVersion": "batch/v1",
    "kind": "Job",
    "metadata": {
      "name": name,
      "namespace": job_namespace,
      "labels": { "app": "lunanexa-offline-artifact-job" },
      "annotations": { "lunanexa.io/plan-sha256": binding },
    },
    "spec": {
      "backoffLimit": 0,
      "activeDeadlineSeconds": 600,
      "ttlSecondsAfterFinished": 3600,
      "template": {
        "metadata": { "labels": { "app": "lunanexa-offline-artifact-job" } },
        "spec": {
          "restartPolicy": "Never",
          "automountServiceAccountToken": false,
          "enableServiceLinks": false,
          "securityContext": {
            "runAsNonRoot": true,
            "runAsUser": 65532,
            "runAsGroup": 65532,
            "fsGroup": 65532,
            "seccompProfile": {
              "type": "Localhost",
              "localhostProfile": "lunanexa/offline-worker.json",
            },
          },
          "affinity": {
            "podAffinity": {
              "requiredDuringSchedulingIgnoredDuringExecution": [
                {
                  "labelSelector": {
                    "matchLabels": {
                      "app": "lunanexa-offline-artifact-dispatcher",
                    },
                  },
                  "topologyKey": "kubernetes.io/hostname",
                },
              ],
            },
          },
          "initContainers": [
            container(
              "prepare", "/usr/local/bin/offline-artifact-worker", "prepare", false,
            ),
            container(
              "render", "/usr/local/bin/offline-pdf-renderer", "render", true,
            ),
          ],
          "containers": [
            container(
              "finalize", "/usr/local/bin/offline-artifact-worker", "finalize", true,
            ),
          ],
          "volumes": [
            {
              "name": "work",
              "persistentVolumeClaim": { "claimName": state_claim },
            },
            {
              "name": "fonts",
              "persistentVolumeClaim": { "claimName": font_claim },
            },
            { "name": "tmp", "emptyDir": { "sizeLimit": "256Mi" } },
          ],
        },
      },
    },
  }
}

///|
fn pinned_image(image : String) -> Bool {
  let pieces = image.split("@sha256:").to_array()
  pieces.length() == 2 &&
  pieces[0].length() > 0 &&
  pieces[1].length() == 64 &&
  pieces[1].all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f'))
}

///|
async fn kubectl(args : Array[String]) -> (Int, String) {
  let process_env : Map[String, String] = {
    "PATH": "/usr/local/bin:/usr/bin:/bin",
  }
  for
    name in ["KUBECONFIG", "KUBERNETES_SERVICE_HOST", "KUBERNETES_SERVICE_PORT"] {
    if @env.get_env_var(name) is Some(value) {
      process_env[name] = value
    }
  }
  let (code, output) = @async.with_timeout(30000, () => {
    @process.collect_stdout(
      required("LUNANEXA_KUBECTL_BIN"),
      args,
      extra_env=process_env,
      inherit_env=false,
    )
  })
  let bytes = output.binary()
  if bytes.length() > 1048576 {
    raise Failure("Kubernetes job response exceeds limit")
  }
  (code, @utf8.decode(bytes))
}

///|
async fn execute_kubernetes(root : String) -> Unit {
  let image = required("LUNANEXA_OFFLINE_ARTIFACT_JOB_IMAGE")
  if !pinned_image(image) {
    raise Failure("artifact Job image must be digest pinned")
  }
  let job_namespace = required("LUNANEXA_OFFLINE_ARTIFACT_JOB_NAMESPACE")
  let state_claim = required("LUNANEXA_OFFLINE_ARTIFACT_STATE_PVC")
  let font_claim = required("LUNANEXA_OFFLINE_ARTIFACT_FONT_PVC")
  let secret = required("LUNANEXA_OFFLINE_RENDER_SECRET_NAME")
  let prefix = required("LUNANEXA_OFFLINE_ARTIFACT_STATE_SUBPATH")
  if !filename(job_namespace) ||
    !filename(state_claim) ||
    !filename(font_claim) ||
    !filename(secret) ||
    !filename(prefix) {
    raise Failure("invalid Kubernetes deployment reference")
  }
  let parts = root.split("/").to_array()
  let directory = parts[parts.length() - 1].to_owned()
  if directory.length() != 64 ||
    !directory.all(c => c.is_ascii_digit() || (c >= 'a' && c <= 'f')) {
    raise Failure("unexpected artifact job directory")
  }
  let job_bytes = @fs.read_file("\{root}/job.json").binary()
  let binding = digest(@utf8.encode(image + "|" + @utf8.decode(job_bytes)))
  let name = "offline-artifact-" + directory[0:40].to_owned()
  let manifest = artifact_job_manifest(
    name,
    job_namespace,
    image,
    prefix + "/" + directory,
    state_claim,
    font_claim,
    secret,
    binding,
  )
  let manifest_path = "\{root}/kubernetes-job.json"
  write_atomic(manifest_path, @utf8.encode(manifest.stringify()))
  let (existing_status, _) = kubectl([
    "-n", job_namespace, "get", "job", name, "-o", "json",
  ])
  if existing_status != 0 {
    let (created, _) = kubectl([
      "-n", job_namespace, "create", "-f", manifest_path,
    ])
    if created != 0 {
      raise Failure("artifact Kubernetes Job creation failed")
    }
  }
  let deadline = @async.now() + 660000L
  while @async.now() < deadline {
    let (status, body) = kubectl([
      "-n", job_namespace, "get", "job", name, "-o", "json",
    ])
    if status != 0 {
      raise Failure("artifact Kubernetes Job unavailable")
    }
    let current = @json.parse(body)
    guard current
      is {
        "metadata": {
          "annotations": { "lunanexa.io/plan-sha256": String(actual), .. },
          ..
        },
        ..
      } &&
      actual == binding else {
      raise Failure("artifact Kubernetes Job identity mismatch")
    }
    if current is { "status": { "succeeded": Number(value, ..), .. }, .. } &&
      value >= 1 {
      return
    }
    if current is { "status": { "failed": Number(value, ..), .. }, .. } &&
      value >= 1 {
      ignore(
        kubectl(["-n", job_namespace, "delete", "job", name, "--wait=false"]),
      )
      raise Failure("artifact Kubernetes Job failed")
    }
    @async.sleep(2000)
  }
  raise Failure("artifact Kubernetes Job observation timed out")
}

///|
async fn execute_artifact_pipeline(root : String) -> Unit {
  match required("LUNANEXA_OFFLINE_ARTIFACT_EXECUTION_BACKEND") {
    "kubernetes" => execute_kubernetes(root)
    "development-subprocess" => {
      execute(required("LUNANEXA_OFFLINE_ARTIFACT_WORKER_BIN"), root, "prepare")
      execute(required("LUNANEXA_OFFLINE_RENDERER_BIN"), root, "render")
      execute(
        required("LUNANEXA_OFFLINE_ARTIFACT_WORKER_BIN"),
        root,
        "finalize",
      )
    }
    _ => raise Failure("artifact execution backend must be explicitly selected")
  }
}
