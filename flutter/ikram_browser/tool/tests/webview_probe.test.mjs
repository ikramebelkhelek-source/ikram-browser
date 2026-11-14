// Exercise the actual CLI and its CDP replies without an Android SDK.
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";
import test from "node:test";

function probe(mode, phase = "verify") {
  const root = mkdtempSync(join(tmpdir(), "webview-probe-"));
  const evidence = join(root, "probe.json");
  const token = "a".repeat(32);
  // Mock the browser boundary, not the probe's assertions or exit handling.
  const setup = `
    globalThis.fetch = async () => ({ json: async () =>
      [{type:"page", webSocketDebuggerUrl:"ws://mock"}] });
    globalThis.WebSocket = class extends EventTarget {
      constructor() { super(); queueMicrotask(() => this.dispatchEvent(new Event("open"))); }
      close() {}
      send(raw) {
        const {id, method, params} = JSON.parse(raw);
        let result = {};
        if (method === "Runtime.evaluate") result = {result:{value:
          params.expression.includes("document.readyState") ? {
            secure:true, origin:"https://update-test.invalid", path:"/${phase}",
            cookie:${mode !== "lost-js"}, storage:${mode !== "lost-storage"}
          } : true }};
        if (method === "Network.getCookies") result = {cookies:
          ["update_js","update_http"].filter(name => ${mode !== "lost-http"} || name !== "update_http")
          .map(name => ({name, value:"${token}", secure:true, expires:9999999999, httpOnly:name==="update_http"}))};
        // A read-only verification must never send a Set-Cookie header.
        if (method === "Fetch.fulfillRequest" && ${phase === "verify"} &&
            params.responseHeaders.some(h => h.name === "Set-Cookie")) throw Error("verify reseeded");
        queueMicrotask(() => this.dispatchEvent(new MessageEvent("message", {data:JSON.stringify(
          ${mode === "cdp-failure"} && method === "Page.enable"
          ? {id,error:{message:"CDP unavailable"}} : {id,result})})));
        if (method === "Page.navigate") queueMicrotask(() =>
          this.dispatchEvent(new MessageEvent("message", {data:JSON.stringify({
            method:"Fetch.requestPaused", params:{requestId:"fixture",
              request:{url:"https://update-test.invalid/${phase}"}}
          })})));
      }
    };
  `;
  try {
    const result = spawnSync(process.execPath, [
      "--import", `data:text/javascript,${encodeURIComponent(setup)}`,
      fileURLToPath(new URL("../probe_webview.mjs", import.meta.url)),
      phase, token, evidence,
    ], { encoding: "utf8", timeout: 10000 });
    assert(!result.error, result.error?.message);
    return { code: result.status, evidence: JSON.parse(readFileSync(evidence, "utf8")),
      stderr: result.stderr };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("CLI verifies the original JS/HttpOnly cookies and localStorage read-only", () => {
  const result = probe("intact");
  assert.equal(result.code, 0, result.stderr);
  assert.equal(result.evidence.status, "passed");
});

test("CLI distinguishes each kind of storage loss from protocol failures", () => {
  for (const mode of ["lost-js", "lost-storage", "lost-http"]) {
    const result = probe(mode);
    assert.equal(result.code, 3, result.stderr);
    assert.equal(result.evidence.status, "data-loss");
  }
  const failed = probe("cdp-failure");
  assert.equal(failed.code, 1);
  assert.equal(failed.evidence.status, "probe-failure");
});
