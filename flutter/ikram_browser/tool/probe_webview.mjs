// Node 22 built-ins only. Talks to the REAL app WebView over forwarded CDP.
// Fetch interception serves a controlled HTTPS-origin document without a public
// service, custom CA, personal account, or bypass of certificate errors.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const [phase, token, evidence, port = "9222"] = process.argv.slice(2);
assert(["seed", "verify"].includes(phase), "Expected seed or verify");
assert(/^[a-f0-9]{32}$/.test(token), "Expected a synthetic random token");
const origin = "https://update-test.invalid";
const template = readFileSync(fileURLToPath(new URL("./update_test_page.html", import.meta.url)), "utf8");
const body = Buffer.from(template.replace("__TOKEN__", JSON.stringify(token))).toString("base64");
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const target = targets.find(t => t.type === "page" && t.webSocketDebuggerUrl);
assert(target, "No inspectable app WebView");
const ws = new WebSocket(target.webSocketDebuggerUrl);
const pending = new Map();
let sequence = 0;
let failure;
let legacyInterception = false;
const deadline = setTimeout(() => {
  console.error("Timed out checking WebView storage");
  process.exit(1);
}, 60000);
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve, { once: true });
  ws.addEventListener("error", reject, { once: true });
});
function send(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
}
ws.addEventListener("message", event => {
  const message = JSON.parse(event.data);
  if (message.id) {
    const call = pending.get(message.id);
    if (!call) return;
    pending.delete(message.id);
    if (message.error) call.reject(new Error(JSON.stringify(message.error)));
    else call.resolve(message.result);
  } else if (["Fetch.requestPaused", "Network.requestIntercepted"].includes(message.method)) {
    const { requestId, interceptionId, request } = message.params;
    const url = new URL(request.url);
    // Block every other request while probing: no external websites needed.
    const controlled = url.origin === origin && url.pathname === `/${phase}`;
    const headers = [{ name: "Content-Type", value: "text/html; charset=utf-8" },
      { name: "Cache-Control", value: "no-store" }];
    if (controlled && phase === "seed") {
      headers.push({ name: "Set-Cookie", value:
        `update_http=${token}; Max-Age=86400; Secure; HttpOnly; SameSite=Lax; Path=/` });
    }
    const responseBody = controlled ? body : "";
    const delivery = legacyInterception
      ? send("Network.continueInterceptedRequest", {
          interceptionId,
          rawResponse: Buffer.concat([
            Buffer.from(`HTTP/1.1 ${controlled ? "200 OK" : "404 Not Found"}\r\n` +
              headers.map(h => `${h.name}: ${h.value}\r\n`).join("") +
              `Content-Length: ${Buffer.from(responseBody, "base64").length}\r\n\r\n`),
            Buffer.from(responseBody, "base64"),
          ]).toString("base64"),
        })
      : send("Fetch.fulfillRequest", {
          requestId, responseCode: controlled ? 200 : 404,
          responseHeaders: headers, body: responseBody,
        });
    delivery.catch(error => { failure = error; });
  }
});
try {
  await send("Page.enable");
  await send("Network.enable");
  try {
    await send("Fetch.enable", { patterns: [{ urlPattern: "*" }] });
  } catch {
    // Older supported Android images predate the Fetch domain.
    legacyInterception = true;
    await send("Network.setRequestInterception", { patterns: [{ urlPattern: "*" }] });
  }
  const navigation = await send("Page.navigate", { url: `${origin}/${phase}` });
  assert(!navigation.errorText, navigation.errorText);
  let result;
  for (let retry = 0; retry < 100; retry++) {
    if (failure) throw failure;
    try {
      const evaluated = await send("Runtime.evaluate", {
        expression: "document.readyState === 'complete' ? window.updateResult : null",
        returnByValue: true,
      });
      result = evaluated.result?.value;
    } catch (error) {
      if (!/context.*(destroyed|not found)|Cannot find context/i.test(error.message)) throw error;
      // A navigation may briefly replace the old JavaScript context.
    }
    if (result?.path === `/${phase}`) break;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  assert(result?.secure, "Fixture is not a secure HTTPS context");
  assert.equal(result.origin, origin);
  assert.equal(result.path, `/${phase}`);
  assert(result.cookie, "Real JavaScript cookie was lost");
  assert(result.storage, "Real localStorage was lost");
  const { cookies } = await send("Network.getCookies", { urls: [`${origin}/`] });
  for (const name of ["update_js", "update_http"]) {
    const cookie = cookies.find(c => c.name === name);
    assert(cookie && cookie.value === token && cookie.secure && cookie.expires > 0,
      `Persistent Secure cookie ${name} missing`);
    if (name === "update_http") assert(cookie.httpOnly, "HttpOnly flag lost");
  }
  // Wait for a composed frame before ADB takes its evidence screenshot.
  await send("Runtime.evaluate", {
    expression: "new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true))))",
    awaitPromise: true,
  });
  writeFileSync(evidence, JSON.stringify({ phase, result, cookies }, null, 2));
  console.log(`PASS: ${phase}: HTTPS-origin WebView cookies and localStorage`);
} finally {
  clearTimeout(deadline);
  ws.close();
}
