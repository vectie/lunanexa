# GLM API and TRAE quickstart

Public guide: <https://suanli.kechuangfuwu.com:8443/docs/?page=client-api>.
Connection and settings verified on 2026-10-16.

| Setting | Value |
| --- | --- |
| Base URL | `https://suanli.kechuangfuwu.com:8443/user/v1` |
| Full chat URL | `https://suanli.kechuangfuwu.com:8443/user/v1/chat/completions` |
| Model ID | `glm-5.3.flash` |
| Authentication | `Authorization: Bearer <your saved lnx_ secret>` |
| Recommended output | `16384` tokens |

Create a scoped key from **MaaS → Create API key**. In **Account & API keys**,
keys remain masked as `********`; use the eye to reveal the actual `lnx_…`
secret or the copy icon to copy it again while it is active. The `api-key-…`
value is a record ID and cannot authenticate a request. Keep secrets out of
public documentation, public QR codes and support messages.

## TRAE

1. Open **Settings → Models → Add model → Custom model**.
2. Choose **OpenAI Chat Completions**. Enable **Full URL** and paste the full
   chat URL from the table. Set Model ID to `glm-5.3.flash` and enter your own
   saved secret in API key.
3. Expand **Advanced configuration → Context window** and set **Output** to
   `16384`. Choose the **Default** model family and turn image input off for
   this text endpoint. Save and start a new conversation.

If your client uses a base URL instead, use the base URL from the table and
let it append `/chat/completions` once. Keep `:8443` and `/user/v1`.
TRAE documents these controls in its
[official model guide](https://docs.trae.cn/ide_models).

## Terminal examples

Load the saved secret privately into the local `API_KEY` environment variable
using your secret manager. These commands contain no secret and do not send a
request when that variable is empty.

### Model discovery

```sh
test -n "$API_KEY" && curl --fail-with-body --silent --show-error \
  'https://suanli.kechuangfuwu.com:8443/user/v1/models' \
  -H "Authorization: Bearer $API_KEY"
```

### Chat

```sh
test -n "$API_KEY" && curl --fail-with-body --silent --show-error \
  'https://suanli.kechuangfuwu.com:8443/user/v1/chat/completions' \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"glm-5.3.flash","messages":[{"role":"user","content":"Hello"}],"max_tokens":1024,"stream":false}'
```

### Stream

```sh
test -n "$API_KEY" && curl --fail-with-body --silent --show-error --no-buffer \
  'https://suanli.kechuangfuwu.com:8443/user/v1/chat/completions' \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"glm-5.3.flash","messages":[{"role":"user","content":"Hello"}],"max_tokens":1024,"stream":true}'
```

A normal response needs assistant text and a finish reason. A successful
stream has text chunks, a terminal finish reason and `[DONE]`. A stream can
return HTTP 200 with an error event, so inspect its events too.

## Limits and errors

- **Unauthenticated / 401**: use the secret, check expiry/revocation and model
  scope. A key record ID is not a credential.
- **InvalidRequest / max_tokens**: recommended output is `16384`. Current
  policy accepts 1–131072, omission or `null`. Model context capacity and
  output budget are separate settings.
- **RequestBudgetExceeded**: reduce conversation history, attached files or
  tool definitions. The current public request-body ceiling is **1 MiB of
  UTF-8 JSON**. The runtime's 850000-token context does not override it.
- **RuntimeUnavailable**: check that MaaS shows the service ready. Retry a
  new conversation; if the problem persists, give the operator the public
  error and time without a key or private prompt.

The current adapter supports ordinary and streamed text, multipart text,
function calls and tool-result history. Null optional parameters are treated
as omitted. These checks do not claim support for images or arbitrary OpenAI
API extensions.

## Private client connection QR

In the signed-in MaaS page, select **Connection QR** and choose an active saved
key. Its QR appears immediately. Alternatively, create a scoped API key and expand
**Client connection QR** in its key dialog. The QR carries the base URL, model, output
limit and API secret as a generic `openai.connection.v1` JSON descriptor.

The QR stays inside the signed-in flow, works independently of guest Wi-Fi,
and is cleared when its panel closes. It is a credential: scan it only with
your own trusted client. Documentation contains no usable secret or private
QR. Expired or revoked keys cannot be retrieved. A QR does not create or extend authorization.
