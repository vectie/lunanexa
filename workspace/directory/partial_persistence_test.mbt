///|
async test "admission failure retains already durable authority expiry" {
  let temporary = @fs.tmpdir(prefix="lunanexa-partial-admission-")
  defer @fs.rmdir(temporary, recursive=true)
  let path = temporary + "/directory.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("user-1", "subject-1")))
  ignore(
    directory.issue_access_grant(
      access_grant("grant-old", "user-1", Developer, 1500L),
      1000L,
    ),
  )
  ignore(
    directory.issue_access_grant(
      access_grant("grant-live", "user-1", Developer, 10000L),
      1000L,
    ),
  )
  ignore(
    directory.issue_lease(
      workspace_lease("lease-1", "subject-1", Developer, 500L, 10000L, Active),
      1000L,
    ),
  )
  @fs.mkdir(path + ".admissions.next")
  try
    directory.reserve_workload(
      "lease-1",
      "subject-1",
      "tenant-opaque-1",
      TextGenerate,
      "partial-workload",
      "partial-request",
      9000L,
      2000L,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("admission unexpectedly persisted")
  }
  let durable : @workspace.WorkspaceDirectorySnapshot = @json.from_json(
    @json.parse(@fs.read_file(path).text()),
  )
  // Inspect before expiry to avoid repairing divergent memory in the assertion.
  // This is a test input, not a change to any production clock.
  assert_eq(directory.snapshot(1000L), durable)
  @fs.rmdir(path + ".admissions.next")
  directory.reserve_workload(
    "lease-1",
    "subject-1",
    "tenant-opaque-1",
    TextGenerate,
    "partial-workload",
    "partial-request",
    9000L,
    2001L,
  )
}
