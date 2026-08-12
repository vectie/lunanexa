# LunaNexa desktop apps for macOS

LunaNexa ships two Mac desktop shells built with Lepusa:

- **LunaNexa Operator** opens the Rabbita operator console at `/console/`.
- **LunaNexa Enterprise** opens the Rabbita enterprise portal at
  `/enterprise/`; its WebIDE navigation stays on the same management origin at
  `/workbench/`.

The management node remains the only UI and API source of truth. The desktop
apps do not embed a fork of the Rabbita interfaces, a controller, credentials,
or customer data. A centrally deployed UI change therefore reaches browser and
desktop users together. Lepusa owns only the native macOS window, application
bundle, signing handoff, and DMG packaging.

## Security boundary

Production builds accept only an HTTPS management base URL. The resulting
WebView loads the UI and API from the same origin, so LunaNexa does not need a
permissive CORS rule for a custom desktop scheme. Neither app registers a
Lepusa native plugin or capability: a compromised page receives no desktop
filesystem, shell, dialog, or opener authority.

The build argument is an origin only, such as `https://manage.example.com`; it
must not include credentials, a path, query, or fragment.

Operator and enterprise credentials stay in WebView page memory, matching the
browser behavior. They are not written into the application bundle, macOS
preferences, GPU-node metadata, or the model store. The management ingress
must provide a valid TLS certificate and must serve these paths on one origin:

```text
/console/
/enterprise/
/workbench/
/v1/...
```

Do not build a production app against a tenant-controlled or otherwise
untrusted origin. The origin supplies executable UI code and receives the
user's scoped LunaNexa credential.

## Local ad-hoc build

The build host needs macOS, MoonBit, Xcode command-line tools, the system Quick
Look tools, `jq`, and a local Lepusa checkout. By default the script finds
Lepusa next to this repository; set `LEPUSA_ROOT` when it lives elsewhere.

Start the local management site, then build both apps and DMGs:

```sh
LUNANEXA_DESKTOP_ALLOW_HTTP_LOOPBACK=1 \
  sh scripts/build-macos-apps.sh http://127.0.0.1:4878 0.1.0
```

Artifacts are written to:

```text
_build/macos/releases/LunaNexa-Operator-0.1.0-macos-arm64.dmg
_build/macos/releases/LunaNexa-Enterprise-0.1.0-macos-arm64.dmg
```

Each DMG has an adjacent `.sha256` checksum. The architecture suffix follows
the release host (`arm64` or `x86_64`); the current pipeline does not claim a
universal binary unless Lepusa supplies both native runtime slices.

The default signing identity is `-`, which produces an ad-hoc signature for
local integrity and launch testing. An ad-hoc image is not suitable for public
download and does not satisfy Gatekeeper on another Mac.

## Production Developer ID build

Create a notarytool keychain profile once on the release Mac, then provide the
exact Developer ID Application identity and the profile name:

```sh
LUNANEXA_MACOS_SIGNING_IDENTITY='Developer ID Application: Example Corp (TEAMID)' \
LUNANEXA_MACOS_NOTARIZATION_PROFILE='lunanexa-notary' \
  sh scripts/build-macos-apps.sh https://manage.example.com 1.0.0
```

Lepusa signs the staged `.app`, creates the DMG with an Applications shortcut,
signs the disk image, submits it to Apple notarization, and staples the accepted
ticket. The script then verifies each final disk image with `hdiutil`.

Before publishing, verify the final artifacts on a clean Apple Silicon Mac:

```sh
codesign --verify --deep --strict '/Applications/LunaNexa Operator.app'
spctl --assess --type execute --verbose=4 '/Applications/LunaNexa Operator.app'
codesign --verify --deep --strict '/Applications/LunaNexa Enterprise.app'
spctl --assess --type execute --verbose=4 '/Applications/LunaNexa Enterprise.app'
```

Test login, operator refresh, agreement handoff, lease submission, and the
Enterprise-to-WebIDE link against the production management origin. A desktop
release does not replace the UI-to-UI, API, cleanup, and restart-reconciliation
gates in `docs/PLAN.md`.

## Build configuration

The checked-in files under `desktop/` are templates. The build creates concrete
manifests under `_build/macos/config`, injecting only:

- management URLs derived from the one base URL;
- application version;
- generated `.icns` path;
- signing identity and optional notarization profile.

Supported environment variables:

| Variable | Ownership | Purpose |
| --- | --- | --- |
| `LEPUSA_ROOT` | release admin | Lepusa checkout used to build the native runtime |
| `LUNANEXA_DESKTOP_BASE_URL` | global admin | HTTPS management origin when not passed as argument |
| `LUNANEXA_DESKTOP_VERSION` | release admin | application/DMG version |
| `LUNANEXA_MACOS_SIGNING_IDENTITY` | release admin | Developer ID identity; defaults to ad-hoc `-` |
| `LUNANEXA_MACOS_NOTARIZATION_PROFILE` | release admin | local notarytool keychain profile name |
| `LUNANEXA_DESKTOP_ALLOW_HTTP_LOOPBACK` | developer only | permits local `http://127.0.0.1` or `localhost` builds |

No setting above is an enterprise-user preference. Management origin and trust
material are release-admin controlled; locale and page-local workbench
preferences remain user-local in the existing Rabbita clients.
