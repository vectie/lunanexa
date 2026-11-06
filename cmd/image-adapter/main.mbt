///|
async fn main {
  guard @env.args() is [_, config_file, bind] else {
    fail("Usage: image-adapter CONFIG_FILE PRIVATE_BIND")
  }
  let config : @service.Config = @json.from_json(
    @json.parse(@fs.read_file(config_file).text()),
  )
  let service = @service.Service::new(config)
  let server = @http.Server(@socket.Addr::parse(bind))
  defer server.close()
  server.run_forever(
    (request, body, conn) => service.handle(request, body, conn),
    allow_failure=true,
    max_connections=16,
  )
}
