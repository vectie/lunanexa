///|
async test "file journal survives reopen and rejects concurrent writers" {
  let temporary = @fs.tmpdir(prefix="lunanexa-kubernetes-journal-")
  let directory = @fs.realpath(temporary)
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/state.json"
  let transport : @kubernetes.Transport = (_, _, _) => {
    fail("opening a journal must not contact Kubernetes")
  }
  let first = @kubernetes.RuntimeSupervisor::open_file(
    runtime_settings(),
    transport,
    path,
  )
  defer first.close()
  let snapshot = first.snapshot()
  assert_eq(@fs.read_file(path).text(), snapshot)
  try
    @kubernetes.RuntimeSupervisor::open_file(
      runtime_settings(),
      transport,
      path,
    )
  catch {
    @kubernetes.OwnershipConflict => ()
    _ => fail("wrong concurrent writer error")
  } noraise {
    second => {
      second.close()
      fail("two writers acquired one journal")
    }
  }
  first.close()
  let reopened = @kubernetes.RuntimeSupervisor::open_file(
    runtime_settings(),
    transport,
    path,
  )
  defer reopened.close()
  assert_eq(reopened.snapshot(), snapshot)
}

///|
async test "file journal rejects symlink state files" {
  let temporary = @fs.tmpdir(prefix="lunanexa-kubernetes-symlink-")
  let directory = @fs.realpath(temporary)
  defer @fs.rmdir(directory, recursive=true)
  @fs.write_file(directory + "/unrelated", "untouched", create_mode=CreateNew)
  @fs.symlink(target=directory + "/unrelated", directory + "/state.json")
  try
    @kubernetes.RuntimeSupervisor::open_file(
      runtime_settings(),
      (_, _, _) => fail("unexpected transport"),
      directory + "/state.json",
    )
  catch {
    @kubernetes.InvalidResource => ()
    _ => fail("wrong symlink rejection")
  } noraise {
    opened => {
      opened.close()
      fail("symlink journal accepted")
    }
  }
  assert_eq(@fs.read_file(directory + "/unrelated").text(), "untouched")
}
