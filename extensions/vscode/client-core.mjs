import { createHash } from "node:crypto";

export const LEGACY_TOKEN_SECRET = "lunanexa.inferenceBearerToken";
const ORIGIN_TOKEN_SECRET_PREFIX = "lunanexa.inferenceBearerToken.v2.";

/**
 * Parse a URL that is safe for requests carrying LunaNexa credentials.
 *
 * @param {string | URL} value
 * @param {string} label
 * @returns {URL}
 */
export function secureUrl(value, label) {
  let url;
  try {
    url = new URL(value instanceof URL ? value.toString() : value);
  } catch {
    throw new Error(`${label} is not a valid absolute URL.`);
  }

  if (url.username || url.password || url.search || url.hash) {
    throw new Error(
      `${label} must not contain credentials, query parameters, or a fragment.`,
    );
  }
  const loopback =
    url.hostname === "localhost" ||
    url.hostname === "127.0.0.1" ||
    url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(loopback && url.protocol === "http:")) {
    throw new Error(
      `${label} must use HTTPS (HTTP is permitted only for loopback development).`,
    );
  }
  return url;
}

/**
 * Return the canonical origin and its SecretStorage key. Paths never affect
 * the binding, while a host, scheme, or non-default port change always does.
 *
 * @param {string | URL} value
 */
export function tokenBindingForUrl(value) {
  const url = secureUrl(value, "API base URL");
  const origin = url.origin;
  const digest = createHash("sha256").update(origin, "utf8").digest("hex");
  return {
    origin,
    secretKey: `${ORIGIN_TOKEN_SECRET_PREFIX}${digest}`,
  };
}

/**
 * VS Code can retain stale hand-authored workspace values even for settings
 * whose current manifest scope is machine. Treat either workspace layer as an
 * explicit unsafe override instead of relying only on configuration merging.
 *
 * @param {unknown} inspected
 */
export function hasWorkspaceOverride(inspected) {
  return Boolean(
    inspected &&
      typeof inspected === "object" &&
      (inspected.workspaceValue !== undefined ||
        inspected.workspaceFolderValue !== undefined ||
        inspected.workspaceLanguageValue !== undefined ||
        inspected.workspaceFolderLanguageValue !== undefined),
  );
}

/**
 * Select intended text from the canonical output only. The response envelope
 * is deliberately never stringified because it can carry receipts and other
 * metadata that do not belong in the editor preview.
 *
 * @param {unknown} response
 * @param {number} maximum
 * @returns {{ text: string, truncated: boolean }}
 */
export function normalizeSuccessfulText(response, maximum) {
  if (!Number.isInteger(maximum) || maximum < 1) {
    throw new TypeError("The display limit must be a positive integer.");
  }
  if (!response || typeof response !== "object") {
    return { text: "", truncated: false };
  }

  const output = response.output;
  let text;
  if (output && typeof output === "object" && typeof output.text === "string") {
    text = output.text;
  } else if (
    output &&
    typeof output === "object" &&
    typeof output.output_text === "string"
  ) {
    text = output.output_text;
  } else if (typeof output === "string") {
    text = output;
  } else if (output !== undefined && output !== null) {
    try {
      text = JSON.stringify(output, null, 2);
    } catch {
      text = "";
    }
  } else {
    text = "";
  }

  if (typeof text !== "string") {
    return { text: "", truncated: false };
  }
  return {
    text: text.slice(0, maximum),
    truncated: text.length > maximum,
  };
}
