///|
/// Validate a browser API origin. Public HTTP requires an exact deployment
/// opt-in matching both the page and API origin; it never permits cross-origin
/// plaintext credentials. This UI policy is not a replacement for gateway auth.
pub extern "js" fn allows(
  endpoint : String,
  page_origin : String,
  public_http_origin : String,
) -> Bool =
  #| (endpoint, pageOrigin, publicHttpOrigin) => {
  #|   try {
  #|     const url = new URL(endpoint);
  #|     if (url.username || url.password || url.search || url.hash) return false;
  #|     const sameOriginSite = url.protocol === 'https:' && url.origin === pageOrigin && ['/mana', '/user'].includes(url.pathname);
  #|     if (url.pathname !== '/' && !sameOriginSite) return false;
  #|     if (url.protocol === 'https:') return true;
  #|     if (url.protocol !== 'http:') return false;
  #|     if (['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) return true;
  #|     return url.origin === pageOrigin && publicHttpOrigin.split(',').includes(pageOrigin);
  #|   } catch (_) { return false; }
  #| }

///|
extern "js" fn page_origin() -> String =
  #| () => globalThis.location?.origin || ''

///|
extern "js" fn configured_http_origin() -> String =
  #| () => globalThis.document?.querySelector('meta[name="lunanexa-public-http-origin"]')?.getAttribute('content') || ''

///|
/// Read deployment metadata, never query parameters or browser storage.
pub fn endpoint_allowed(endpoint : String) -> Bool {
  allows(endpoint, page_origin(), configured_http_origin())
}
