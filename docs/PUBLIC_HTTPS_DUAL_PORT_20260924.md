# Public HTTPS entry points (2026-09-24)

The three browser sites are exposed only through the shared hostname on HTTPS
443 and HTTPS 8443. The router maps both external ports to
`192.168.2.175:443`; the cluster has one TLS termination and one certificate.
The DNS name and certificate are unchanged. Supported paths on either port:

| Site | Path |
| --- | --- |
| Management | `/mana/` |
| Enterprise | `/user/` |
| Documentation | `/docs/` |

The slash redirects retain the incoming port. The identity gateway accepts
only the exact shared hostname, with either no explicit port or `:8443`.
Operator and enterprise cookies remain separate; the 8443 cookie names are
also distinct from their 443 counterparts so signing in on one port cannot
overwrite a session on the other. Password login and platform self-registration
remain available. The old public Keycloak browser entry point is retired, so
OIDC start is disabled at this shared gateway; Keycloak and its private
integration are not deleted.

The former public IP:port entries 4173, 4174, and 5000–5007 were removed from
public exposure. The relevant Kubernetes Services are `ClusterIP`, the
management-node 5000–5005 forwarding unit is disabled, the host-network 4174
listener is gone, and MoonTown 5007 listens only on loopback. These changes
do not delete accounts, model artifacts, or user work files. Any future public
MoonTown entry must be explicitly routed under the shared HTTPS front door.

Verification on 2026-09-24:

- Public 8443: valid TLS certificate; all three paths returned HTTP 200;
  `/mana`, `/user`, and `/docs` redirected to their slash-ending URLs while
  retaining `:8443`.
- Public 8443 browser: the existing enterprise test account reached the
  organization portal, and the operator account reached live cluster overview
  with four of four nodes reporting.
- Management LAN to port 443 with the public hostname/SNI: all three paths
  returned HTTP 200 with valid TLS, and exact same-origin authentication
  requests reached the gateway.
- Public IP old web ports 4173, 4174, and 5000–5007 did not serve a page.
- This workstation's external 443 route did not complete a TLS handshake;
  this is a network-path limitation of that observation, not proof that the
  cluster-side 443 listener failed. Public 8443 was verified end to end.

The old temporary HTTP runbook is historical and does not describe the current
public entry points.
