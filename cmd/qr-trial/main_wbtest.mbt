///|
test "trial QR accepts only venue URLs" {
  assert_true(valid_trial_url("https://maas.example.com/?trial=wifi"))
  assert_true(valid_trial_url("https://maas.example.com/user/?trial=wifi"))
  for
    value in [
      "http://maas.example.com/?trial=wifi", "https://YOUR_HOST/user/?trial=wifi",
      "https://user@maas.example.com/user/?trial=wifi", "https://maas.example.com\t/user/?trial=wifi",
      "https://maas.example.com/user/?trial=wifi#token", "https://maas.example.com/user/?trial=wifi&key=secret",
      "https://maas.example.com/other/?trial=wifi",
    ] {
    assert_false(valid_trial_url(value))
  }
}

///|
test "trial QR SVG has a four-module quiet zone and no embedded URL" {
  let url = "https://maas.example.com/user/?trial=wifi"
  let svg = trial_svg(url)
  assert_true(svg.has_prefix("<svg "))
  assert_true(svg.contains("width=\"512\" height=\"512\""))
  assert_true(svg.contains("<path fill=\"black\" d=\"M"))
  assert_true(svg.contains("h1v1h-1z"))
  assert_false(svg.contains(url))
  assert_true(svg.has_suffix("</svg>\n"))
}
