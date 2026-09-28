///|
test "host-root adapter invokes only the fixed helper under chroot" {
  let action = [
    "sanitize", "--lease-id", "lease-1", "--authorization", "signed",
  ]
  let (program, args) = helper_invocation(action, Some("/host"))
  assert_eq(program, "/usr/sbin/chroot")
  assert_eq(args, [
    "/host", "/usr/libexec/lunanexa-lease-helper", "sanitize", "--lease-id", "lease-1",
    "--authorization", "signed",
  ])
  let (default_program, default_args) = helper_invocation(action, None)
  assert_eq(default_program, "/usr/bin/sudo")
  assert_eq(default_args[0], "--non-interactive")
  let mut rejected = false
  try helper_invocation(action, Some("/tmp")) catch {
    _ => rejected = true
  } noraise {
    _ => ()
  }
  assert_true(rejected)
}
