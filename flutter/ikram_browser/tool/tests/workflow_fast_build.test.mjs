import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const workflow = readFileSync(
  new URL('../../../../.github/workflows/android-apk.yml', import.meta.url),
  'utf8',
);
function job(id) {
  const section = workflow.split(`\n  ${id}:\n`)[1];
  assert.ok(section, `Missing workflow job ${id}`);
  return section.split(/\n  [a-z][a-z-]*:\n/)[0];
}
const publish = job('publish-tested-apk');
const condition = publish.match(/    if: >-\n((?:      .+\n)+)/)[1]
  .trim().replace(/\s+/g, ' ')
  .replace(/needs\.([\w-]+)/g, 'needs["$1"]');
// Evaluate the workflow's actual boolean gate, rather than a copied policy.
const canPublish = new Function(
  'inputs', 'needs', 'always', 'cancelled', `return (${condition});`,
);
function gate({ extended, failed, historical = 'success', available = 'true',
                cancelled = false } = {}) {
  const needs = Object.fromEntries(
    ['build', 'verify-update', 'retain-baseline', 'verify-historical-update',
      'backup-runtime-checks'].map(id => [id, { result: 'success' }]),
  );
  if (!extended) {
    for (const id of Object.keys(needs)) {
      if (id !== 'build') needs[id].result = 'skipped';
    }
  } else {
    needs['verify-historical-update'].result = historical;
  }
  if (failed) needs[failed].result = 'failure';
  needs['retain-baseline'].outputs = { available };
  return canPublish({ extended_checks: extended }, needs, () => true, () => cancelled);
}

test('push and default dispatch publish after one signed build without slow checks', () => {
  assert.equal(gate(), true);
  assert.equal(gate({ extended: false }), true);
  assert.match(workflow, /extended_checks:[\s\S]*?type: boolean[\s\S]*?default: false/);
  assert.match(job('build'), /sequence:.*fromJSON\(inputs.extended_checks == true && '\[1, 2\]' \|\| '\[2\]'\)/);
  assert.match(publish, /name: signed-apk-2-/);
  assert.match(job('build'), /environment: android-signing/);
  assert.match(job('build'), /verify_apk_certificate\.py/);
  assert.match(job('build'), /github\.ref == format\('refs\/heads\/\{0\}'/);
});

test('failed signed builds and cancelled runs cannot publish in either mode', () => {
  for (const extended of [undefined, false, true]) {
    assert.equal(gate({ extended, failed: 'build' }), false);
    assert.equal(gate({ extended, cancelled: true }), false);
  }
});

test('all slow jobs require explicit opt-in and have time limits', () => {
  for (const id of ['backup-runtime-checks', 'retain-baseline', 'build-test',
                    'verify-update', 'verify-webview-update', 'verify-historical-update']) {
    assert.match(job(id), /inputs\.extended_checks == true/, id);
    assert.match(job(id), /timeout-minutes: \d+/, id);
  }
  assert.doesNotMatch(job('checks'), /gradlew|android-emulator-runner/);
  assert.match(job('checks'), /timeout --kill-after=15s 180s flutter test --timeout 30s/);
  assert.match(job('checks'), /timeout-minutes: 4/);
});

test('extended mode still enforces backup and device checks', () => {
  assert.equal(gate({ extended: true }), true);
  for (const failed of ['verify-update', 'retain-baseline', 'backup-runtime-checks']) {
    assert.equal(gate({ extended: true, failed }), false, failed);
  }
  assert.equal(gate({ extended: true, historical: 'failure' }), false);
  assert.equal(gate({ extended: true, historical: 'skipped' }), false);
  assert.equal(gate({ extended: true, historical: 'skipped', available: 'false' }), true);
});

test('fast summary does not claim skipped migration or backup checks passed', () => {
  assert.match(publish, /if \[ "\$EXTENDED_CHECKS" = true \]; then/);
  assert.match(publish, /Extended checks skipped/);
  assert.match(publish, /does not certify backup transfer or browsing-data preservation/);
  assert.match(publish, /not an app-store release/);
});
