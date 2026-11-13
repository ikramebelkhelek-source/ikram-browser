import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
import test from "node:test";

const token = "a".repeat(32);
const page = readFileSync(new URL("../update_test_page.html", import.meta.url), "utf8");
const script = page.match(/<script>([\s\S]*?)<\/script>/)[1]
  .replace("__TOKEN__", JSON.stringify(token));

function visit(path, cookies = "", storage = new Map(), secure = true) {
  let writes = 0;
  const document = {
    get cookie() { return cookies; },
    set cookie(value) { writes++; cookies = value.split(";")[0]; },
    getElementById() { return {}; },
  };
  const window = { isSecureContext: secure };
  vm.runInNewContext(script, {
    document, window, isSecureContext: secure,
    location: { pathname: path, origin: "https://update-test.invalid" },
    localStorage: {
      getItem(key) { return storage.get(key) ?? null; },
      setItem(key, value) { writes++; storage.set(key, value); },
    },
  });
  return { result: window.updateResult, writes, cookies, storage };
}

test("seed writes real browser APIs and verify only reads them", () => {
  const seeded = visit("/seed");
  assert.equal(seeded.writes, 2);
  assert(seeded.result.cookie && seeded.result.storage && seeded.result.secure);
  const verified = visit("/verify", seeded.cookies, seeded.storage);
  assert.equal(verified.writes, 0);
  assert(verified.result.cookie && verified.result.storage);
});

test("verify exposes lost cookies or localStorage without repairing either", () => {
  for (const [cookies, storage] of [
    ["", new Map()],
    [`update_js=${token}`, new Map()],
    ["", new Map([["android_update_token", token]])],
    ["update_js=wrong", new Map([["android_update_token", "wrong"]])],
  ]) {
    const verified = visit("/verify", cookies, storage);
    assert.equal(verified.writes, 0);
    assert(!(verified.result.cookie && verified.result.storage));
  }
});

test("an insecure document cannot claim a secure HTTPS context", () => {
  assert.equal(visit("/seed", "", new Map(), false).result.secure, false);
});
