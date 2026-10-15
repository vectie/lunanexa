# Hosted Moon app refresh — 2026-10-15

## Diagnosis

The authenticated application catalog launched immutable images whose content
had not been refreshed with the current host source. A source or host build
does not change either the gateway's configured image or existing workspace
deployments. MoonDesk and MoonTown still used September image releases.

MoonRobo's workspace retained the lightweight example URDF rather than the
host's full Noetix E1 asset pack. The simplified model had only one mesh; the
complete model has 25. The local CAD/URDF pack remains outside Git.

## Published release

| Application | Immutable image digest |
| --- | --- |
| MoonDesk | `sha256:583fabbb45d177de3b5266d17f1d3f9cc90991fad26647cb0e8b6c9bb89beac1` |
| MoonTown desktop and miniapp | `sha256:ae5b5ed4abf0976fafefcf0f2312fe9a77f9b09ab483d3fc46ba444e60a94052` |
| MoonRobo | `sha256:6a37bad4b1460aaa144fd817f628fd181a6220f9af6e83353bb3cd782a8cd3f5` |

These images are in the deployment's private `moon/hosted-apps` repository.
Native and browser artifacts were built from current working source snapshots,
including local paired MoonLeaf/MoonLib and MoonChat dependencies where required.
The frontend builds retain `/moondesk/`, `/moonrobo/` and MoonTown's dynamic
platform-base contract. Source snapshots include existing uncommitted product
work; their content is not represented solely by a clean Git revision.

Launch profiles and all existing application workspace deployment specifications
now use these images. Previously inactive workspaces remain inactive. The
MoonTown miniapp image was updated alongside its desktop. Gateways were
restarted to load their current profiles. Workspace PVCs and existing files
were preserved; these applications remain on the CPU workspace host.

MoonRobo now packages the reviewed digital model beside its UI. Its own native
host initializes an absent model, preserves an existing model directory, and
refuses symlink destinations and nonregular model assets. Directory publication
uses the portable POSIX operation because NFS rejects `RENAME_NOREPLACE`.
The live model contains 25 resolved meshes and zero missing meshes. Existing
telemetry/joint-mapping diagnostics remain separate from model-file readiness;
this update makes no physical robot readiness claim.

The Linux MoonDesk link required `-lutil` for its terminal `forkpty` dependency.
This was supplied by the private Linux build compiler wrapper alongside
`-pthread -ldl`. The existing upstream compiler migration warnings remain;
this record does not claim warning-free builds of the sibling applications.
MoonTown's assembled current frontend is 72.2 MiB; its narrow size gate is now
73 MiB and reports the actual configured budget.

## Verification

- All three Linux native release builds completed successfully.
- MoonDesk and MoonRobo production Vite builds completed successfully.
- MoonTown's production verifier checked all 306 files and their checksums.
- Both MoonRobo model installer regressions passed natively: preserved customer
  edits and refused destination symlinks.
- Every active application workspace was ready after rollout.
- Served application indexes exactly matched the host build artifacts:
  - MoonDesk: `238fe493e1aac64a339e7902d89f9cc3582da67b2710dcafebbb552997438c43`
  - MoonTown: `e65fc1215dbe1b58bed8b2aa255ab61a00ac0541a99e6e5447edbe90d47018fa`
  - MoonRobo: `14062ee10d14be4ae3cf248ec4fb04adbf7e203ec6837b47f2dae7cae6456bae`
- All three product health routes returned HTTP 200.
- Each running native application binary exactly matched its current Linux
  build by SHA-256, independently of its frontend.
- The actual MoonRobo base-link mesh returned HTTP 200 and matched the original
  reviewed asset checksum. Snapshot inspection confirmed 25 resolved meshes.
- Temporary model publication/inspection Jobs, their NetworkPolicies, failed
  installer staging directories and the temporary host listener were removed.

## Authenticated browser acceptance

The customer renewed the `/user/` session as guojiaan. Fresh launches from the
PaaS cards reached all three current applications through their live gateways.

- MoonRobo rendered the full E1 body in its robot view. The live renderer
  reported 50/50 visual and collision mesh loads, covering 25 model meshes and
  25 collision overlays. The source was the full E1 URDF. The preserved legacy
  RoboBook still reports two joint-name mapping diagnostics; they were not
  hidden or relabelled as physical readiness.
- MoonDesk opened the current Desk and Code destinations, preserved its existing
  conversations, and returned a new GLM reply of exactly `42` to a bounded
  verification request that prohibited tools and file changes.
- MoonTown opened its current map, navigated into Talent and back, preserved
  its earlier guide conversation, and produced a new guide answer explaining
  that real work results are available in the Dashboard. Character creation
  remains an explicit first-use action; none was created for this check.

Screenshots of the live robot, MoonDesk response and MoonTown map/guide were
retained as local review artifacts outside Git. These observations are scoped
to the signed-in account and do not assert that every account or physical
robot was exercised.

Deployment backups, original RoboBook files, credentials and production
snapshots remain private host references and are not committed here.
