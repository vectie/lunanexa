# Guest Wi-Fi QR trial

The visitor QR code opens the enterprise portal with `?trial=wifi`. It contains
only the public URL. It does not contain an API key, Wi-Fi password, bearer
token or reusable grant. After connecting to the venue guest Wi-Fi, the visitor
scans the code, signs in or registers, and selects **Activate one-hour trial**.
The account receives the existing shared-inference entitlement for exactly one
hour, with the configured model allowlist and request quota. The clock does not
pause or restart when the visitor leaves Wi-Fi or scans again.

## Configure the venue

1. Confirm the guest Wi-Fi has a dedicated egress IPv4 address or narrow CIDR
   that other networks cannot use. Record the address from the trusted ingress,
   not from a browser-supplied header. If multiple networks share the same NAT,
   source IP cannot prove guest Wi-Fi membership; use a network gateway with a
   distinct egress before enabling this profile.
2. Ensure only the trusted TLS ingress can reach the identity gateway. The
   ingress must **overwrite** `X-Real-IP` with its observed client address and
   must discard untrusted forwarding headers. Test this at the gateway for the
   exact production path, including any CDN, load balancer and direct-IP edge.
   IPv6 clients fail closed until a separately reviewed IPv6 profile exists.
3. Set `LUNANEXA_WIFI_TRIAL_SOURCE_CIDRS` on the identity gateway to the
   comma-separated guest egress CIDRs, such as `198.51.100.27/32`. An empty
   value disables redemption. Invalid CIDRs fail gateway startup. Never use a
   broad public range.
4. Set `LUNANEXA_WIFI_TRIAL_ENABLED=1` on the controller. This disables
   automatic open-registration trials so a visitor cannot bypass the one-hour
   network check. Configure `LUNANEXA_WIFI_TRIAL_MAXIMUM_REQUESTS` (default
   `100`) and `LUNANEXA_WIFI_TRIAL_ALLOWED_MODELS` (default `text.qwen`) for
   reviewed, published shared-inference models. The gateway and controller
   must share the deployment-owned `LUNANEXA_IDENTITY_ASSERTION_SECRET`.
5. Generate the physical QR from the **actual** enterprise portal URL. For a
   shared-host installation, the URL is
   `https://YOUR_HOST/user/?trial=wifi`; for a dedicated enterprise host, use
   `https://YOUR_ENTERPRISE_HOST/?trial=wifi`. Run LunaNexa's native MoonBit
   generator with the real URL:

   ```sh
   moon run cmd/qr-trial -- 'https://maas.your-venue.example/user/?trial=wifi' visitor-trial.svg
   ```

   Replace the example host before printing. The generator refuses placeholders
   and will not overwrite an existing file. The SVG is a deployment artifact,
   not a source-controlled credential. Print the guest Wi-Fi joining
   instructions beside the QR; the QR itself is the trial URL.

## Acceptance

- On guest Wi-Fi, scan the printed QR with a phone, sign in with a verified
  account, and activate. `/v1/auth/trial` must show an expiry exactly 3,600,000
  milliseconds after its start and the configured quota and models.
- On mobile data or another network, activation must return
  `WifiTrialNetworkRequired` without creating an entitlement. Spoofed
  `X-Real-IP`, `X-Forwarded-For`, or a Wi-Fi SSID in the browser must not help.
- Repeated activation with the same account must preserve the original expiry.
  A different existing trial must not be converted or extended.
- Invoke an allowed model within the quota and reject another model. After the
  deadline, the session, API key and workspace path must deny trial access.
  Restart the controller during the trial and repeat the expiry check.

These are deployment acceptance steps. Repository tests cover CIDR parsing,
gateway proof, and entitlement duration; they cannot establish that a real
visitor joined the physical Wi-Fi.
