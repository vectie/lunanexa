///|
/// Hosted portal applications reuse the current HTTPS origin. A deployment's
/// catalog can name the alternate ingress port, whose browser session is
/// deliberately separate. External and desktop clients keep their own URI.
extern "js" fn hosted_application_uri(
  launch_uri : String,
  portal_endpoint : String,
) -> String =
  #| (launchUri, portalEndpoint) => {
  #|   try {
  #|     const target = new URL(launchUri);
  #|     const portal = new URL(portalEndpoint);
  #|     const portalPort = port => port === '' || port === '8443';
  #|     if (target.protocol === 'https:' && portal.protocol === 'https:' &&
  #|         target.hostname === portal.hostname &&
  #|         !target.username && !target.password &&
  #|         portalPort(target.port) && portalPort(portal.port) &&
  #|         target.pathname.startsWith('/user/business/')) {
  #|       return portal.origin + target.pathname + target.search + target.hash;
  #|     }
  #|   } catch (_) {}
  #|   return launchUri;
  #| }
