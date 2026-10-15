///|
/// A QR code carries only this public URL. Strictly require the trial landing
/// path so a placeholder, secret-bearing URL, or different endpoint cannot be
/// printed as a venue trial by mistake.
fn valid_trial_url(url : String) -> Bool {
  if !url.has_prefix("https://") ||
    url.length() > 1024 ||
    url.contains("@") ||
    url.contains("#") ||
    url.contains("\\") ||
    url.contains("\n") ||
    url.contains("\r") ||
    url.contains(" ") {
    return false
  }
  let authority_and_path = url[8:].to_owned()
  let host = authority_and_path.split("/").to_array()[0]
  let path = authority_and_path[host.length():].to_owned()
  host.length() > 0 &&
  host.length() <= 253 &&
  host
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '.' ||
    c == '-' ||
    c == ':'
  }) &&
  (path == "/?trial=wifi" || path == "/user/?trial=wifi") &&
  host != "YOUR_HOST" &&
  host != "YOUR_ENTERPRISE_HOST" &&
  !host.contains("?") &&
  !host.contains("://")
}

///|
fn trial_svg(url : String) -> String raise {
  if !valid_trial_url(url) {
    raise Failure(
      "expected a public HTTPS enterprise URL ending in /?trial=wifi or /user/?trial=wifi",
    )
  }
  let qr = @qr.encode_medium(url)
  let size = qr.size()
  let canvas = size + 8
  let svg = StringBuilder()
  svg.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"512\" height=\"512\" viewBox=\"0 0 ",
  )
  svg.write_string(canvas.to_string())
  svg.write_string(" ")
  svg.write_string(canvas.to_string())
  svg.write_string(
    "\" role=\"img\" aria-label=\"Scan to open the LunaNexa guest trial\" shape-rendering=\"crispEdges\">",
  )
  svg.write_string(
    "<title>LunaNexa guest trial</title><rect width=\"100%\" height=\"100%\" fill=\"white\"/><path fill=\"black\" d=\"",
  )
  for y in 0..<size {
    for x in 0..<size {
      if qr.is_black(x, y) {
        svg.write_string("M")
        svg.write_string((x + 4).to_string())
        svg.write_string(" ")
        svg.write_string((y + 4).to_string())
        svg.write_string("h1v1h-1z")
      }
    }
  }
  svg.write_string("\"/></svg>\n")
  svg.to_string()
}

///|
async fn main {
  guard @env.args() is [_, url, output] else {
    fail("usage: moon run cmd/qr-trial -- PUBLIC_TRIAL_URL OUTPUT.svg")
  }
  let svg = trial_svg(url)
  @fs.write_file(output, svg, create_mode=CreateNew, permission=0o644)
  println("QR SVG written to \{output}")
}
