///|
test "GLM control origin comes from the site and has no path or credentials" {
  assert_true(@glmcontrol.valid_origin("http://10.1.2.3:5907"))
  assert_true(@glmcontrol.valid_origin("https://glm-control.example.test:5907"))
  for
    rejected in [
      "", "http://", "ftp://10.1.2.3:5907", " http://10.1.2.3:5907", "http://user@10.1.2.3:5907",
      "http://10.1.2.3:5907/path", "http://10.1.2.3:5907?token=x", "http://10.1.2.3:5907#fragment",
    ] {
    assert_false(@glmcontrol.valid_origin(rejected))
  }
}
