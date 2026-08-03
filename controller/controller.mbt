///|
pub fn health(version : String) -> @contracts.HealthResponse {
  @contracts.health("controller", version)
}
