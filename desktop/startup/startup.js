(() => {
  "use strict";

  const config = globalThis.LUNANEXA_DESKTOP_CONFIG;
  const card = document.querySelector(".startup-card");
  const edition = document.querySelector("#product-edition");
  const title = document.querySelector("#startup-title");
  const message = document.querySelector("#status-message");
  const eyebrow = document.querySelector("#status-eyebrow");
  const origin = document.querySelector("#management-origin");
  const route = document.querySelector("#application-route");
  const transport = document.querySelector("#required-transport");
  const retry = document.querySelector("#retry-button");
  const attempt = document.querySelector("#attempt-state");
  const diagnostics = document.querySelector("#diagnostics");

  let activeController = null;

  const fail = (detail) => {
    card.classList.add("is-error");
    eyebrow.textContent = "CONNECTION UNAVAILABLE";
    title.textContent = "Management node could not be reached";
    message.textContent =
      "LunaNexa stayed on this safe startup screen. Check the management service and network, then retry.";
    attempt.textContent = detail;
    retry.hidden = false;
    retry.disabled = false;
    diagnostics.hidden = false;
    retry.focus();
  };

  const validConfig = () => {
    if (!config || typeof config !== "object") return false;
    if (typeof config.targetUrl !== "string" || !config.targetUrl) return false;
    if (typeof config.managementOrigin !== "string" || !config.managementOrigin) return false;
    if (!Number.isInteger(config.probeTimeoutMs)) return false;
    return config.probeTimeoutMs >= 1000 && config.probeTimeoutMs <= 30000;
  };

  const connect = async () => {
    if (!validConfig()) {
      fail("Invalid desktop release configuration");
      return;
    }

    activeController?.abort();
    activeController = new AbortController();
    card.classList.remove("is-error");
    eyebrow.textContent = "MANAGEMENT CONNECTION";
    title.textContent = "Connecting to LunaNexa";
    message.textContent =
      "Checking the configured management node before opening the app.";
    attempt.textContent = "Checking…";
    retry.hidden = true;
    retry.disabled = true;
    diagnostics.hidden = true;

    const timer = globalThis.setTimeout(
      () => activeController.abort(),
      config.probeTimeoutMs,
    );

    try {
      await fetch(config.targetUrl, {
        method: "GET",
        mode: "no-cors",
        credentials: "include",
        cache: "no-store",
        redirect: "follow",
        signal: activeController.signal,
      });
      globalThis.clearTimeout(timer);
      attempt.textContent = "Connected · opening app";
      globalThis.location.replace(config.targetUrl);
    } catch (error) {
      globalThis.clearTimeout(timer);
      const timedOut = error && error.name === "AbortError";
      fail(timedOut ? "Connection timed out" : "Connection failed");
    }
  };

  if (!validConfig()) {
    origin.textContent = "Invalid release configuration";
    route.textContent = "—";
    transport.textContent = "HTTPS in production";
  } else {
    document.title = config.productName;
    edition.textContent = config.edition;
    origin.textContent = config.managementOrigin;
    route.textContent = config.applicationRoute;
    transport.textContent = config.managementOrigin.startsWith("https://")
      ? "HTTPS"
      : "Loopback HTTP · development only";
  }

  retry.addEventListener("click", connect);
  connect();
})();
