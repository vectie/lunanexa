# Management foundation deployment through the UI

This runbook installs one host as LunaNexa's management, PostgreSQL,
model-data and storage foundation. It does **not** enroll that host as a
production GPU worker. An Ascend accelerator on the same host may be qualified
later through the separate temporary-compute path; the future DGX Spark nodes
remain the production compute fleet.

No access node is assumed. The installer connects to the selected SSH targets
directly or through an operator-owned OpenSSH alias/`ProxyJump`. That optional
network edge is not registered in LunaNexa and is not required for daily API,
browser or node-agent traffic. Management and compute are logical roles: this
host may carry both only when temporary compute is explicitly selected and
qualified; production placement remains a separate policy decision.

The first deployment intentionally omits public ingress. Operators reach the
web tier through a protected Kubernetes port-forward until a reviewed TLS edge,
client identity policy and stable hostname are available.

For the current physical-host campaign, management Apply is under a network
freeze. The verified host baseline is `br-ngfw-in` with only `eni3`, static
`192.168.2.175/24`, default route `192.168.2.1`, and no DHCP address on that
bridge. `eni0` is deliberately not a bridge member. The installer does not run
Netplan, `networkctl`, NetworkManager, bridge, route, firewall, K3s restart or
reboot commands. Before and after Apply, retain fresh evidence for SSH through
the operator-owned alias, the gateway, external HTTPS, the bridge membership
and the K3s ready endpoint. Stop the deployment if any one of those changes.

## 1. Prepare immutable local images

Build the control image on native Linux amd64. Build the browser bundle and web
image, import both images plus a digest-pinned PostgreSQL image into the target
containerd image store, and record their immutable IDs and archive checksums.
Do not render moving tags that the cluster must pull from the Internet.

The repository now provides:

```sh
sh scripts/build-browser-bundles.sh
sh scripts/deploy/build-management-images.sh RELEASE_TAG
```

The static coursebook image uses a dedicated minimal context containing only
its nginx configuration, public site files, bilingual coursebook JSON,
evidence ledger and screenshots. Do not build it from the broad repository
context: doing so needlessly transfers Moon dependencies, native artifacts and
unrelated source to the container builder even though the final image does not
retain them. For a documentation-only release, run
`scripts/deploy/build-coursebook-image.sh RELEASE_TAG`.

`images/Containerfile.control` supports a normal native amd64 build. When the
operator workstation is ARM and its amd64 emulator cannot run the MoonBit
toolchain reliably, build only the `build-deps` stage there, compile the control
binary in that image on a native amd64 builder, and assemble it with
`images/Containerfile.control-runtime`. Record this as a packaging bypass; it is
not a substitute for a native CI image pipeline.

The PostgreSQL native stub is compiled with an explicit optimized profile. Do
not remove its `-O2` flag: pinned Zig debug-mode C compilation otherwise emits
UBSan references that are absent from the optimized controller link. A build
that reaches the final controller translation unit and then reports
`__ubsan_handle_*` is a packaging failure, not a reason to add a sanitizer
runtime to the production image. Restore the reviewed stub flags and rebuild.

## 2. Render non-secret management resources

Every topology-sensitive value is explicit:

```sh
scripts/deploy/render-management-foundation.sh \
  --output /ABSOLUTE/RENDERED_DIRECTORY \
  --management-node KUBERNETES_NODE_NAME \
  --control-image IMMUTABLE_LOCAL_CONTROL_REFERENCE \
  --web-image IMMUTABLE_LOCAL_WEB_REFERENCE \
  --postgres-image IMMUTABLE_LOCAL_POSTGRES_REFERENCE \
  --model-store-root /data/models \
  --control-uid HOST_MODEL_STORE_UID \
  --control-gid HOST_MODEL_STORE_GID \
  --runtime-endpoint http://127.0.0.1:19090/v1/responses \
  --public-api-base-url https://gpu.example.com \
  --commercial-provider-action-origin https://provider.example \
  --s3-region cn-east-1 \
  --controller-epoch 1
```

The loopback runtime is an explicit pending adapter. It lets the management
plane start without claiming that inference is available. Replace it only after
a real runtime passes qualification, and increment `controller-epoch` for every
controller generation that may encounter existing durable state.

The renderer emits `management.yaml` at mode `0600`, pins every workload to the
selected management node, uses `imagePullPolicy: Never`, removes configured-but-
invalid offline readiness and direct-node runtime documents, and rejects unsafe
paths, images, endpoints and unresolved placeholders. It also places a SHA-256
digest of the management configuration on the control Pod template, so an
approved ConfigMap correction triggers a deterministic rollout on the next
Apply instead of leaving the old process running.

## 3. Generate the protected secret manifest

Create a new file; the generator refuses to overwrite an existing one:

```sh
scripts/deploy/generate-management-secrets.sh \
  /ABSOLUTE/PROTECTED_DIRECTORY/management-secrets.yaml
```

The output is mode `0600` and contains four Kubernetes Secrets:

- `lunanexa-control-credentials` with distinct 256-bit authorities;
- `lunanexa-database` with the PostgreSQL database, user, password and URL;
- `lunanexa-cosign-trust` with a public verification key only;
- `lunanexa-offline-commerce-readiness` as an explicit pending mount.

Every generated hex authority is exactly 64 printable bytes without a trailing
line feed. Do not regenerate and apply the database Secret after PostgreSQL has
initialized unless the database role password is rotated in the same reviewed
transaction; changing only the Kubernetes Secret will break authentication.

Do not commit, upload to the documentation site, paste into the browser or copy
the contents into a terminal transcript. Back it up in the deployment secret
provider before the first apply.

## 4. Preview and apply through the installer UI

Start the loopback-only companion and open `/installer/` from the generated web
bundle. Select **Management foundation** and fill only these references:

For unattended local handoff, set `LUNANEXA_INSTALLER_TOKEN_FILE` to a new
absolute protected path when starting the companion. This avoids placing the
ephemeral bearer in terminal scrollback; the file must be deleted after the
installer session ends.

1. companion endpoint and ephemeral session token;
2. SSH user, explicit SSH port, private-key path and pinned `known_hosts` path;
3. management Kubernetes node name and SSH host;
4. namespace, kubeconfig, rendered directory and protected management-secret
   manifest path.

Click **Preview and verify**. A successful preview must show all of the
following before it enables Apply:

- protected operator-side paths accepted;
- pinned SSH identity accepted without password or host-key prompt;
- management host disk/model-store inspection complete;
- the selected Kubernetes node is `Ready`;
- Kubernetes control plane, CoreDNS and metrics API are reachable;
- a bounded list of differing non-secret Kubernetes resource identities is
  shown; protected Secret data is never diffed;
- no unresolved placeholder and no cluster mutation.

Type `DEPLOY MANAGEMENT` exactly, review the terminal again and click
**Deploy management foundation**. The UI then labels only the management node,
creates the namespace, applies the protected secret manifest, applies the
reviewed combined management manifest, then waits for PostgreSQL plus the
control, console, enterprise, workbench
and model-source workloads and requires a ready endpoint for all six Services.
If `ingress.yaml` is absent it prints an explicit protected-port-forward notice.

## 5. Access the installed UI without public ingress

On the trusted operator machine:

```sh
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  port-forward service/lunanexa-console 4174:8080
```

Open `http://127.0.0.1:4174/console/`. The web image proxies `/v1`, `/health`,
`/ready` and `/version` to `lunanexa-control` inside the namespace, so the UI
and API remain same-origin. Use `/enterprise/` and `/workbench/` on the same
origin for their respective views.

### Temporary public HTTP exception

When an operator explicitly accepts plaintext transport risk and an existing
router rule is fixed as `WAN :4174 -> 192.168.2.175:4174`, the management
overlay includes `lunanexa-console-public`. K3s ServiceLB binds host port 4174
and sends it to the dedicated `lunanexa-console-public-gateway` Deployment.
The gateway is deliberately separate from the private console Pod; its
NetworkPolicy permits inbound HTTP but limits egress to cluster DNS and the
LunaNexa controller. The controller admits only that exact gateway label.

This exception is reachable at
`http://106.39.18.146:4174/console/`. It is not suitable for credentials,
contracts, customer data or production operation because HTTP does not protect
tokens from interception. Replace it with reviewed TLS and remove the temporary
Service as soon as external validation is complete.

The same reviewed overlay can expose two non-operator sites through separate
ServiceLB gateways when the router already owns these exact rules:

- `WAN :4173 -> 192.168.2.175:4173` serves the static bilingual coursebook at
  `http://106.39.18.146:4173/`;
- `WAN :3000 -> 192.168.2.175:3000` serves the user workbench at
  `http://106.39.18.146:3000/workbench/`.

The coursebook gateway has no egress. This first public package is the static
coursebook only: the guide-pet and coursebook administration APIs remain
disabled until their authenticated service is packaged and reviewed. The
workbench gateway may reach only cluster DNS and `lunanexa-control:8080`.
Public plaintext remains temporary; scoped user credentials must move behind
TLS before real customer use. Both credential-bearing browser surfaces fail
closed on public HTTP: the operator console disables its operator/audit fields
and the workbench disables its scoped-token field and Connect action. Use those
surfaces only through protected localhost or HTTPS.

## 6. Acceptance checks

Do not call the deployment healthy until all checks pass:

```sh
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa get pods,svc,pvc
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  rollout status statefulset/lunanexa-postgres --timeout=5m
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  wait --for=jsonpath='{.status.updatedReplicas}'=3 \
  deployment/lunanexa-control --timeout=5m
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  wait --for=jsonpath='{.status.replicas}'=3 \
  deployment/lunanexa-control --timeout=5m
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  wait --for=jsonpath='{.status.availableReplicas}'=1 \
  deployment/lunanexa-control --timeout=5m
kubectl --kubeconfig /ABSOLUTE/KUBECONFIG -n lunanexa \
  rollout status deployment/lunanexa-model-source --timeout=5m
curl --fail http://127.0.0.1:4174/health
curl --fail http://127.0.0.1:4174/ready
curl --fail http://106.39.18.146:4173/health
curl --fail --location http://106.39.18.146:3000/
curl --fail http://106.39.18.146:3000/health
curl --fail http://106.39.18.146:3000/ready
```

Then verify through the browser that console, enterprise and workbench load,
language switching works, API-backed summary/readiness pages return real data,
and an unauthenticated privileged action is rejected.

## 7. Incident and correction record (2026-08-27)

| Observation | Root cause | Correction and evidence |
|---|---|---|
| Installer silently assumed a four-compute-node topology | Management and compute concerns shared one request shape | Added explicit management, compute expansion, management-plus-selected-compute and local-simulation scopes with separate validation and confirmation phrases; no production path assumes a compute count |
| Compute expansion required an unrelated management-host SSH target | Shared remote validation treated every operation as a full-cluster install | Compute-only scope now uses the existing kubeconfig/API plus only the selected compute SSH targets; management fields are cleared and ignored |
| Access/bastion host was treated as a likely architecture role | Reachability was confused with LunaNexa topology | Documented direct access and optional operator-owned OpenSSH/VPN transit; neither is registered as a LunaNexa node role |
| Management Preview displayed five stages while Apply executed six | The management-node label mutation was absent from the typed stage list | Installer v4 now displays the label stage explicitly; tests assert 6 management, 7 compute, 10 combined and 5 simulation stages |
| Apply could report success after waiting only for the controller | PostgreSQL and the three browser deployments were not part of the rollout gate | Apply now waits for the PostgreSQL StatefulSet plus control, console, enterprise and workbench deployments, then requires a ready endpoint for all five Services |
| Apply reported success while a replacement ModelSource Pod was `RunContainerError` | The later ModelSource component was never added to the installer's rollout and endpoint lists, so the old ready replica masked the broken replacement | Added `lunanexa-model-source` to both gates and to the installer harness assertions; the final image rolled to a new `1/1 Running`, zero-restart Pod before acceptance continued |
| The native ModelSource binary built on the physical amd64 host but failed to link | The executable used async threads and TLS without explicitly linking the older host's pthread and dynamic-loader libraries | Added `-pthread -ldl` to `cmd/model-source/moon.pkg`; targeted native deny-warn checks and eight ModelSource tests pass |
| The first corrected ModelSource image failed with `permission denied` | The native builder emitted mode `0770 root:root`, while the runtime intentionally uses UID/GID 65532 | Normalized the packaged binary to mode `0555`, emitted a new immutable image tag instead of mutating the failed tag, previewed exactly one Deployment diff and observed a ready zero-restart replacement |
| Companion bearer appeared in terminal scrollback | The launcher only printed the generated token | Added an exclusive-create, mode-`0600` token-file handoff; startup tests prove no bearer appears in output and overwrite attempts fail |
| Switching scopes retained hidden compute/kubeconfig values | Form transitions only hid fields | Scope transition now clears values that are not owned by the selected topology; UI regression tests cover local → management and full → management |
| K3s current stable would not start | Host boots cgroup v1; Kubernetes 1.36 rejects it | Removed the failed install and pinned K3s `v1.34.10+k3s1` temporarily; cgroup-v2/OS migration remains required |
| All system pods stayed `ContainerCreating` | Containerd could not reach Docker Hub for the pause image | Installed the checksum-verified, version-matched official K3s air-gap bundle under `/var/lib/rancher/k3s/agent/images`; after one controlled restart CoreDNS, local storage, metrics-server and Traefik became healthy |
| MoonBit installer segfaulted in an amd64 container on ARM Colima | QEMU user-mode emulation failed while bundling core | Compiled on native amd64 in the verified dependency image, verified the resulting ELF/checksum and assembled a runtime-only image |
| Native dependency build could not resolve packages | Bare `moon fetch` is invalid in the current toolchain | Replaced it with `moon update`; native build completed with zero errors |
| Linux build read invalid `.mbt` files | macOS AppleDouble `._*` metadata entered the archive | Excluded AppleDouble and `.DS_Store` files from image contexts and cleaned only the isolated temporary build directory |
| Web image could not find browser assets | `.dockerignore` excluded all `_build` output | Allowed only `_build/browser-dist/**`; native pod smoke returned HTTP 200 for all four pages and JavaScript bundles |
| Workbench was absent after management apply | Installer manifest loop omitted `workbench.yaml` | Workbench is required in split-manifest mode and included in the combined renderer; missing-workbench test fails closed |
| TLS ingress was assumed to exist | Base nginx-specific ingress was applied unconditionally on K3s/Traefik | Ingress is now optional; the initial foundation uses protected port-forwarding until a reviewed TLS overlay exists |
| Controller secrets were disconnected from the UI | Management apply had no explicit protected secret input | Installer request v3 adds a management-secret manifest path, validates mode `0400`/`0600`, and applies it before workloads |
| Duplicate heartbeat rows could replace a missing compute node | Heartbeat verifier counted rows but not distinct selected IDs | Gate now requires the selected response IDs to be unique; duplicate, missing, wrong-ID, stale, future and inactive fixtures fail |
| Embedded terminal repeated harmless `.bashrc` bind warnings | Remote account invokes `bind` during non-interactive SSH | Companion collapses only that exact warning into one notice; other `.bashrc` failures remain visible |
| ARM-local nginx smoke reset connections | The test executed an amd64 image under ARM emulation | Result was not counted; the image was imported and retested as a native K3s pod |
| `/data/models` exists on the root filesystem | No dedicated model/data volume is mounted yet | Preflight prints a notice and the deployment records this as temporary, not durable model storage |
| Compute Preview treated `npu-smi` plus a container engine as sufficient | Host hardware detection was confused with Kubernetes capacity and a qualified LunaNexa runtime adapter | Ascend now fails closed until the device plugin, CANN runtime, telemetry collector and OCI supervisor adapter are reviewed; NVIDIA enrollment additionally requires positive Kubernetes `nvidia.com/gpu` capacity |
| Both public SSH forwards closed before an SSH banner | The operator reachability path stopped forwarding to a responding SSH service; direct LAN SSH and the prior Kubernetes tunnel were also unavailable | Performed read-only handshakes only, changed no network state, paused UI Apply/model staging, and added a bounded Preview blocker that requires restoring SSH/forwarding plus pinned identity before retry |
| The router learned DHCP address `192.168.2.9` instead of the required static entry point, and connecting both LAN paths disrupted the switch | `br-ngfw-in` combined `eni3` and `eni0` with STP disabled while DHCP and static `192.168.2.175` were both active; forwarding evidence proved the management router and access node were behind `eni3` | Used timed `netplan try`, verified a fresh SSH session plus gateway/DNS/HTTPS, retained only `eni3`, made `.175` the sole static address/default-route source and detached stale `eni0`; both direct public SSH and the access-node path then succeeded |
| The installer reopened with the obsolete fixed-four-node JavaScript after rebuilding | `installer/index.html` used a manually maintained query version, so the browser reused an older asset | Browser bundle generation now derives the query version from the built installer JavaScript SHA-256; a cache-free `/installer/` load displays the topology-neutral management/compute scopes without a manual URL suffix |
| A reloaded public console/workbench could still execute an older JavaScript bundle after an image rollout | Console, enterprise and workbench indexes also carried manually maintained query versions, so an open browser tab could outlive the deployed code | Browser bundle generation now derives all four script query versions from each built JavaScript SHA-256. The live public console and workbench HTML expose the expected content digests, and fresh UI loads show the transport gates from the deployed image |
| Public workbench allowed a scoped bearer to be typed over plaintext HTTP even though the eventual request was rejected | The transport check lived only in the Connect command; credential entry itself remained possible on an interceptable origin | The workbench now disables the token field and Connect action before entry on non-loopback HTTP and renders an explicit HTTPS/localhost warning. A Rabbita regression test and a live public-browser check cover the gate |
| ModelScope downloads required manual refresh and a failed/cancelled import could never be retried | Import state had cancellation but no retry transition, and the console had no generation-fenced progress polling | Added deterministic retry of the same import identity, automatic 1.5-second active-download polling, logout/stale-result fencing and explicit Retry UI. Store and UI regressions cover restart recovery, nonterminal retry rejection and stale poll suppression |
| A restarted ModelScope import could report more than 100% or re-download an already complete file | Durable operation counters were reused as if they described the current transfer, while the file loop started again from the first path | Import execution now reconstructs counters from zero, reuses a complete file only after size/SHA-256 verification, resumes a partial file with a bounded Range request, and falls back to a clean per-file restart when Range is unsupported |
| All three browser pods crashed while the image itself passed an HTTP smoke test | Hardened Deployments set `readOnlyRootFilesystem: true`, but nginx needed runtime scratch space under `/tmp` | Mounted a dedicated `emptyDir` at `/tmp` for console, enterprise and workbench; the renderer regression test requires all three mounts while preserving the read-only root filesystem |
| The control pod rejected the reviewed administrator settings as `InvalidGlobalSetting` | MoonBit's derived JSON contract encodes `Int64` values as strings, while the deployment example and ConfigMap used JSON numbers | Corrected every `Int64` field in both deployment artifacts and added a native integration test that parses the exact operator-facing example through the production settings parser |
| Correcting the settings ConfigMap did not recover the crashing control pod | Kubernetes updates a mounted ConfigMap but does not automatically replace an existing Pod, so rollout status kept observing the pre-fix process | The renderer now hashes the reviewed management configuration into the control Pod template; a changed policy/configuration forces a normal Deployment rollout through the installer UI |
| Control startup rejected `invalid provider callback secret configuration` | `openssl rand -hex -out` left a trailing line feed in every generated credential; the provider callback transport correctly permits printable bytes only | The generator now writes exactly 64 hexadecimal bytes with no terminator, and tests decode every emitted control credential plus the database password and assert the exact byte length |
| Retrying after a post-fence startup failure reported only `DurableStoreError.InvalidState` | The failed process had already acquired controller epoch 1; the next process correctly rejected reuse, hiding the earlier provider-secret error in the newest log | Captured the previous-container log, incremented the reviewed controller generation for recovery, made the rendered configuration digest include the epoch patch, and added a bounded startup log that names an epoch rejection without exposing state or secrets |
| A tempting repair was to generate and apply an entirely new secret set | PostgreSQL had already initialized against the original database authority, so silently rotating only the Kubernetes Secret would strand the database | Live repair must preserve the database, trust and readiness entries and preserve each control credential while removing only its trailing line feed; secret extraction into a protected operator file requires explicit authorization and is never printed to terminal or browser |
| Preview accepted the newline-bearing provider credential and discovered it only after control startup | The installer checked only file mode and placeholders, not the decoded Secret resource contract | Preview now locally normalizes the manifest through `kubectl create --dry-run=client`, requires exactly the four reviewed Secret resources and exact key sets, rejects reused authorities, and requires `provider-callback-secret` to decode to exactly 64 lowercase hexadecimal bytes before any SSH or cluster mutation |
| Normalizing every legacy credential made `deployments.json` fail integrity verification | The empty deployment snapshot had already been signed with the original catalog authority including its legacy line feed; changing that authority correctly looked like tampering | Recovery restores every previously used authority byte-for-byte and trims only the provider callback key whose transport forbids the line feed; new installations use the corrected generator for every key. This is a compatibility migration, not an integrity bypass |
| A Preview-side Secret check briefly depended on the live API and the local SSH tunnel dropped | `kubectl apply --dry-run=client` still retrieved current object configuration, turning a local format check into a network operation | Replaced it with `kubectl create --dry-run=client --validate=false`; the Secret shape/byte check is now local, while the later explicit Kubernetes-context stage remains the sole API reachability gate. The tunnel was restored with a local SSH forward only; host networking and K3s were unchanged |
| A namespace-less generated Secret manifest failed Preview after otherwise valid byte checks | `kubectl create --dry-run=client` defaulted those local objects to `default`, and the verifier then compared that synthetic namespace with the selected `lunanexa` namespace | The local normalization now includes `--namespace "$cluster_namespace"`; absent namespaces resolve to the selected target while an explicitly conflicting namespace remains invalid. The installer regression test asserts the namespace argument |
| Router port 4174 accepted TCP but returned an empty HTTP response | The working listener was a Mac-local `kubectl port-forward`; no process on `192.168.2.175:4174` served the router's DNAT target | After explicit acceptance of temporary plaintext risk, added an isolated K3s ServiceLB gateway on 4174. Directly targeting the private console remained blocked by NetworkPolicy, so the final design uses a separately labeled gateway with minimal controller/DNS egress instead of broadening the private console policy |
| Public workbench root redirected clients to `:8080/workbench/` | nginx expanded a relative `return 302` using its container listen port instead of the ServiceLB/NAT port | Set `absolute_redirect off`, packaged a new immutable image, verified `Location: /workbench/` in-container and externally, then rolled only the public workbench gateway |
| New controller reached PostgreSQL but restarted with `controller epoch is stale` | Epoch 7 was already fenced by the serving replica; preserving it across a controller replacement correctly failed closed | Incremented the reviewed controller epoch to 8, retained the exact PostgreSQL image and all authorities, and observed a zero-restart ready cutover while the epoch-7 replica continued serving until replacement |
| The amd64 control build stopped although the Docker container was not marked `OOMKilled` | The Colima VM, rather than the individual build container, exhausted memory while QEMU executed the large generated controller translation unit; the VM kernel killed unrelated processes as well | Treated the VM kernel OOM record as authoritative, recovered the exact generated inputs, cross-compiled the translation unit with the pinned Zig toolchain and linked it in a disposable native Linux environment. A successful container exit flag alone is not sufficient build evidence |
| The ModelSource image filled the Colima disk after its MoonBit and Zig toolchains had already been copied | `COPY . .` copied the repository-local toolchains a second time into `/src`, adding hundreds of megabytes that were not source inputs | The ModelSource image now copies only `moon.mod`, `.mooncakes`, `modelsource` and `cmd/model-source`. The runtime image contains only the resulting executable and its runtime dependencies |
| Public workbench HTML returned `200` while `/health` returned `502` | Gateway egress admitted the controller, but the controller ingress policy omitted `lunanexa-workbench-public-gateway`; static assets therefore masked a completely broken API path | Added the workbench gateway as an explicit controller peer and a bounded manifest regression test that requires both console and workbench gateways in the controller ingress rule; live acceptance must probe workbench `/health` and `/ready`, not only its HTML |
| Management Preview proved reachability but did not show what Apply would change | Validation stopped after context and manifest checks, so an operator repairing one policy had no bounded change plan in the UI | Preview now runs `kubectl diff` only for the reviewed non-secret management manifest, emits resource identities rather than raw payloads, excludes the protected Secret manifest, and fails closed when the diff fails or cannot be summarized |

## 8. Executed UI acceptance record (2026-08-27)

This is an action record, not a claim that unexecuted scenarios passed.

| Order | Page/control | Atomic action | Observed result |
|---:|---|---|---|
| 1 | `/installer/` · Language | Selected `简体中文` | Installer labels, confirmation guidance and embedded terminal rendered in Chinese |
| 2 | Deployment target | Selected `管理基础` | Form showed only management SSH, Kubernetes and local artifact references; it did not infer an access node or compute fleet |
| 3 | Local companion | Entered the loopback companion endpoint and its ephemeral installer-session token | Companion accepted the browser session; the token was not printed in the embedded terminal |
| 4 | SSH trust | Entered `HwHiAiUser`, port `22`, the pinned private-key path, pinned `known_hosts` path and host alias `lunanexa-management` | Preview used `BatchMode=yes`, `IdentitiesOnly=yes` and strict host-key checking; no password prompt occurred |
| 5 | Kubernetes/artifacts | Entered node `ubuntu`, namespace `lunanexa`, the protected tunneled kubeconfig, rendered manifest directory and protected Secret-manifest path | All values remained references; Secret values were never put in the browser |
| 6 | `预览并验证` | Clicked Preview with the first targeted legacy-compatible Secret file | Preview failed closed before SSH because namespace-less dry-run objects appeared as `default`; no resource changed |
| 7 | `预览并验证` | Added the explicit target namespace to the protected temporary manifest and clicked Preview again | All operator-path, pinned-SSH, host, Kubernetes-context, Secret-contract and placeholder checks passed; terminal ended with `no resources were changed` |
| 8 | Confirmation phrase | Entered `DEPLOY MANAGEMENT` | Apply became enabled only after the successful Preview and exact phrase |
| 9 | `部署管理基础` | Clicked Deploy once | Namespace and reviewed resources reconciled; the controller rolled to the new configuration digest and epoch |
| 10 | Embedded terminal | Watched all six stages through completion | PostgreSQL, control, console, enterprise and workbench rollouts succeeded; all five Services had ready endpoints; terminal ended with `management-foundation is reconciled` |
| 11 | Independent post-check | Rechecked the management host and Kubernetes API without changing network state | Gateway ping passed, Baidu HTTPS returned `200`, K3s was `active`, `/readyz` returned `ok`, and every LunaNexa Pod was `1/1 Running` with zero restarts |
| 12 | Protected port-forward | Forwarded `127.0.0.1:4174` to `service/lunanexa-console:8080` and opened `/console/` | The deployed image loaded from the cluster; it was not the local demo bundle |
| 13 | Controller connection | Expanded the credential drawer with all token fields empty | UI reported `Credentials required`; privileged refresh remained disabled and no protected data was shown |
| 14 | Primary navigation | Clicked Overview, Alerts, Nodes, Models, Catalog, Deployments, Requests, Users & access, Leases, Cost centers, Agreements, Offline commerce, Contract documents, Policies, Qualified services, Benchmarks and Audit | Every control opened the correspondingly named level-one page; no route dead-end or blank shell appeared |
| 15 | Console Language | Selected `简体中文` on the deployed Audit page | Navigation, connection drawer, heading and empty-state copy switched to Chinese without reload or mojibake |
| 16 | `/enterprise/` | Opened the deployed enterprise shell on the same protected origin | The Chinese overview rendered successfully; no missing bundle or route failure appeared |
| 17 | `/workbench/` | Opened the deployed user workbench on the same protected origin | The shell rendered `工作区尚未就绪`, truthfully reflecting that no user lease/workspace has been provisioned |
| 18 | Public `:4174` gateway | Opened `http://106.39.18.146:4174/console/` after the isolated gateway rollout | Browser rendered the complete console; `/console/`, `/health` and `/ready` returned HTTP 200, bare `/` returned 302, and the gateway Pod was `1/1 Running` with zero restarts |
| 19 | Public `:4173` coursebook | Opened the deployed root, selected `简体中文`, and inspected the visible navigation and first lesson | The browser reached `/?page=welcome`; navigation, course copy and controls rendered in Chinese without mojibake; `/health` returned `static-coursebook` |
| 20 | Public `:3000` workbench | Opened the bare origin, followed its redirect and selected `简体中文` | The root emitted relative `Location: /workbench/`; the browser rendered the Chinese connection gate, disabled the scoped-token field and Connect action with an HTTPS/localhost warning, and truthfully showed `工作区尚未就绪` |
| 21 | Protected console · Models | Searched ModelScope for `MiniCPM` | UI returned 362 results and displayed `OpenBMB/MiniCPM5-1B` with identity, Apache-2.0 license, task, parameter count and 2.0 GiB size |
| 22 | `OpenBMB/MiniCPM5-1B` · Download | Started the durable import, then retried the same failed identity after adapter fixes | UI reused four verified files and progressed through 3%, 43%, 77% and 100%; no manual model-store bypass was used |
| 23 | Model import terminal state | Refreshed the task after transfer completion | UI showed `校验和已验证`, `100% · 11/11` and the explicit warning that download completion is not user approval |
| 24 | Approval gate | Inspected **批准供用户使用** after checksum verification | The control remained disabled and listed the missing signature, license/evaluation and qualified-runtime/template evidence |
| 25 | Installer · ModelSource range-12 | Previewed one immutable image change and clicked Deploy | Preview reported exactly one non-secret Deployment diff, but the new Pod failed `permission denied`; the installer incorrectly reported completion while the old replica remained ready |
| 26 | Installer · ModelSource range-13 | Corrected only binary execute permissions, generated a new immutable tag, Previewed and clicked Deploy | Preview again reported exactly one non-secret Deployment diff; replacement Pod became `1/1 Running` with zero restarts and a ready endpoint |
| 27 | Independent post-check | Checked every namespace workload plus protected/public HTTP health | All nine Pods were Running with zero restarts; every Deployment/StatefulSet was ready; protected console and public `:4174`, `:4173`, `:3000` health paths returned success |
| 28 | Installer regression proof | Previewed the already-reconciled range-13 manifest and applied it unchanged after fixing the verifier | Preview stated that the reviewed manifest already matched; Apply explicitly waited for `deployment/lunanexa-model-source` and required `service/lunanexa-model-source` to have a ready endpoint before reporting reconciliation complete |
| 21 | Public operator login | Opened `:4174/console/` without credentials and selected `简体中文` | No cluster data or navigation shell was visible; both authority fields and Login were disabled with an explicit public-HTTP/TLS warning |
| 22 | Live ModelScope proxy | Sent a bounded authenticated `MiniCPM` search through a localhost-only controller port-forward | Controller-to-adapter egress returned live `OpenBMB/MiniCPM5-1B` and `OpenBMB/MiniCPM-V-4.6` catalog rows; the mounted operator authority was never printed or entered in the public browser |
| 23 | Public browser asset identity | Reloaded the deployed console and workbench, then inspected the served index documents | Both pages loaded content-derived SHA-256 query versions; the visible transport gates came from the current immutable rollout rather than a stale browser bundle |
| 24 | Public coursebook · deployment lesson | Opened a fresh live browser tab after the static-content rollout and waited for the localized page to render | The Chinese lesson rendered the protected ModelScope search/download/approval-gate recipe and MiniCPM pilot warning; the table of contents linked to the new section and no private LAN address appeared in public assets |

### Post-acceptance immutable rollout snapshot

The ModelSource recovery rollout was imported into the management K3s image
store from one checksum-verified archive and then reconciled without changing
host networking. The retained archive SHA-256 is
`86b3b32ccee064cd51a3f248fa161551188ffad1f38cb9c376d83afee8386ead`.
The exact image manifests are:

- control `lunanexa/control:management-20260827-modelsource-recovery-7` —
  `sha256:7984f1291ebd4caffe66858accf9b409c19d2d6df2776faf1f162dea11c046f2`;
- ModelSource `lunanexa/model-source:management-20260827-modelsource-recovery-7`
  — `sha256:f7b3de6b46676548f2a8c5444996d31602956a67ee0bc00fc2a6b36554bbd205`;
- browser web `lunanexa/web:management-20260827-modelsource-recovery-7` —
  `sha256:44f626c7a4d2f64c7e6aec41e0754b335f984eafeee6f802d445f1dfd09accae`.

After the controller generation advanced from epoch 8 to 9, Kubernetes
reported both nodes `Ready`, every LunaNexa Pod `1/1 Running`, zero restarts,
and all eight Deployments with one ready, available and updated replica. The
controller returned healthy and ready responses, ModelSource returned healthy,
and an authenticated controller-to-ModelSource durable import listing returned
an empty list. The empty list is expected before the operator starts the first
UI import; it is not evidence that the model catalog is unavailable.

The deployed console index identifies its JavaScript with content digest
`96929fd32f2f306d298aa4ebd993b3603b8f8df28336e7979630e8e02f6f5f26`.
A fresh protected localhost browser load showed the credential-first login
screen and no cluster data before authentication. The public HTTP console and
workbench continued to disable credential entry.

The final bilingual coursebook content-only update uses
`lunanexa/coursebook-static:management-20260827-live-evidence-9`, manifest
`sha256:990f159e071a1e911320be5ac7c2bed721dc6b1b3642e7044d74db82f7e8011c`.
Its transfer archive SHA-256 is
`7d59067043257f721b8889f9051c4a375129ef4133baba5306d5667da0afc370`.
Because the guarded installer has no content-only documentation action, this
single Deployment used a narrow readiness-gated rolling update with automatic
rollback; it did not reapply management resources or change network state.
Native amd64 readiness and external English/Chinese content probes passed.
The ARM workstation's nginx/QEMU `io_setup()` failure was retained as an
emulation limitation and was not counted as an image failure or smoke pass.

Credential-authenticated summary/readiness, enterprise and workbench workflows
were **not** counted as passed in this record. Supplying Kubernetes operator,
audit and inference authorities to a browser session is a distinct sensitive
operation and requires explicit operator authorization. The unauthenticated
gate was verified; no credential was extracted as a workaround.

## 9. Known production gaps

This foundation is usable for controlled validation, but it is not yet an AWS-
class GPU cloud:

- the host OS still uses cgroup v1 and an older kernel;
- PostgreSQL is a single instance with no demonstrated backup, restore, PITR or
  failover;
- `/data/models` and local-path PVCs share the root RAID filesystem;
- images are locally imported rather than signed and pulled from a private
  registry;
- the controller runtime image does not yet bundle the pinned Cosign executable;
- the inference runtime, offline-commerce readiness, notification provider and
  machine credential helper are intentionally pending;
- there is no reviewed public TLS/client-identity edge;
- no Ascend or DGX node has passed temporary or production compute enrollment.

Promote this host only after these gaps have owners, acceptance tests and a
rollback procedure. Co-located temporary compute is allowed only through an
explicit qualification/enrollment scope; the installer never infers it merely
because an accelerator is present.

## 中文快速流程

1. 明确选择“管理基础”，不要填写或隐藏保留计算节点。
2. 用渲染脚本生成不含密钥的 `management.yaml`。
3. 用密钥脚本生成权限为 `0600` 的管理面 Secret 清单，绝不粘贴其内容。
4. 在安装页面填写 SSH、kubeconfig、渲染目录和 Secret 清单的**路径**。
5. 先点“预览并验证”；确认终端写明“未修改任何资源”。
6. 输入 `DEPLOY MANAGEMENT`，再次审核后执行部署。
7. 暂时通过受保护的 `kubectl port-forward` 使用控制台；TLS 入口完成前不开放公网。
8. Ascend 仅走临时测试准入，未来 DGX Spark 通过独立的生产计算节点注册流程加入。
