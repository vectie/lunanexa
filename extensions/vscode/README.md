# LunaNexa for VS Code

This is a small northbound client for LunaNexa's canonical `lunanexa.v1`
provider contract. It can store a scoped bearer token, open the separately
hosted developer workbench, and send an explicitly selected editor range as a
non-streaming `TextGenerate` workload after resolving the active workspace
lease. It requires VS Code 1.100 or newer,
whose Node.js extension host supports ECMAScript module extensions.

## Trust boundary

- The access token is stored only in VS Code `SecretStorage`, under a key bound
  to the canonical API origin. It is never put in workspace/user settings, a
  URL, output, or a log. Changing the scheme, host, or port cannot silently
  reuse a token approved for another origin.
- Only the current non-empty selection is sent after the user invokes
  **LunaNexa: Send Selected Text**. The extension does not send the whole file,
  filename, repository, workspace, language identifier, surrounding text, or
  editor telemetry.
- Every request uses `Ephemeral` retention with caching and training reuse
  disabled. The extension cannot opt selected text into evaluation capture or
  model training.
- HTTPS is mandatory except for `http://localhost`, `127.0.0.1`, or `[::1]`
  development. Redirects are rejected so the bearer token is not forwarded.
- This client provides no DGX login, remote shell, filesystem mount,
  repository checkout, or editor-agent runtime. Those capabilities do not
  belong on a LunaNexa managed node. The manifest classifies the extension as
  a local UI client rather than a remote workspace extension.
- The displayed output is limited to 32 KiB. The client accepts the current
  canonical `output.text` and `output.output_text` shapes, or a bounded JSON
  rendering of the `output` value only. It never renders the whole response.
  Results open as plain text so generated Markdown, images, and HTML cannot
  trigger external requests. Receipts and errors are separately bounded, and
  raw request payloads are never logged.

The opaque subject reference and model alias are normal VS Code configuration,
not secrets. The API URL and subject reference are machine scoped, preventing a
repository from selecting a different credential destination or loopback
identity. Production ingress must replace a client-supplied subject with its
authenticated identity mapping; the explicit setting supports a trusted proxy
or loopback acceptance. Keep identifiers free of personal, project,
repository, and product identity. Use a short-lived token limited to the
`inference` credential scope.

## Configure

Install or run the extension, then set:

- `lunanexa.apiBaseUrl` to the management ingress base URL in VS Code's user or
  machine settings. This setting is machine scoped and workspace overrides are
  refused. The extension posts to `<base>/v1/workloads`.
- `lunanexa.workbenchUrl` to the separately hosted Rabbita workbench.
- `lunanexa.subjectRef` in user or machine settings, to the opaque subject used
  by the trusted identity proxy or loopback controller. Like the API URL, a
  workspace override is refused. The extension discovers tenant scope and
  text-generation limits from `/v1/workspace/self`.
- `lunanexa.modelAlias` to an approved provider-neutral text model alias.
- Optional deadline and maximum-output settings.

Run **LunaNexa: Configure Access Token** from the Command Palette to store the
token securely. Confirm the exact canonical origin shown by the modal. Do not
put a token into `settings.json`. A token saved by the earlier unbound format
is migrated only after the same explicit origin confirmation; cancelling
leaves it unbound and sends nothing.

## Manual test

1. Open this directory in VS Code and press **F5** to launch an Extension
   Development Host.
2. In the development host, configure a loopback test controller such as
   `http://127.0.0.1:8080`, an opaque workspace subject, and a deployed model
   alias.
3. Run **LunaNexa: Configure Access Token** and enter a scoped test credential.
4. Open a scratch document, select only a harmless test phrase, and run
   **LunaNexa: Send Selected Text** from the Command Palette or editor menu.
5. Verify that a preview document shows bounded normalized output and the
   audit receipt. Verify that an empty selection sends nothing.
6. Stop or revoke the test credential and confirm the extension shows only the
   controller's bounded public error and any provided correlation receipt.
7. Run **LunaNexa: Open Developer Workbench** and confirm the configured URL
   opens without credentials in it.

For syntax and pure client-security tests (without installing dependencies),
run:

```sh
npm run check
npm test
```

## Current limitations

The extension does not implement streaming, cancellation, automatic token
issuance/refresh, or external-tool handoffs. It discovers the active
text-generation lease before each invocation, while final access and
concurrency enforcement remain server responsibilities. This initial client
expects a JSON response from `POST /v1/workloads` and shows only the canonical
text output and receipt.
