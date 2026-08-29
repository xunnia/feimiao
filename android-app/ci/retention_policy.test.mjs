import assert from 'node:assert/strict';
import { test } from 'node:test';

import { planRetention } from './retention_policy.mjs';

function release(versionCode, hash) {
  const id = `v${versionCode}-${hash}`;
  return [
    `apk:${id}:0`,
    `apk:${id}:1`,
    `apk:${id}:manifest`,
  ];
}

test('keeps the current and immediately previous complete releases', () => {
  const keys = [
    'version.json',
    ...release(284, 'a'.repeat(12)),
    ...release(283, 'b'.repeat(12)),
    ...release(282, 'c'.repeat(12)),
    'apk:0',
    'apk:manifest',
  ];
  const plan = planRetention(keys, `v284-${'a'.repeat(12)}`);

  assert.deepEqual(plan.keepReleaseIds, [
    `v284-${'a'.repeat(12)}`,
    `v283-${'b'.repeat(12)}`,
  ]);
  assert.equal(plan.keepKeys.includes('version.json'), true);
  assert.equal(plan.deleteKeys.includes(`apk:v282-${'c'.repeat(12)}:0`), true);
  assert.equal(plan.deleteKeys.includes('apk:0'), true);
});

test('fails closed when a higher release exists before the pointer advances', () => {
  const keys = [
    'version.json',
    ...release(284, 'a'.repeat(12)),
    ...release(283, 'b'.repeat(12)),
    ...release(285, 'c'.repeat(12)),
  ];
  assert.throws(
    () => planRetention(keys, `v284-${'a'.repeat(12)}`),
    /newer release keys exist/,
  );
});

test('fails closed for unknown keys', () => {
  assert.throws(
    () =>
      planRetention(
        ['version.json', 'user-data', ...release(284, 'a'.repeat(12))],
        `v284-${'a'.repeat(12)}`,
      ),
    /unknown KV keys/,
  );
});

test('fails closed when the current release manifest is missing', () => {
  assert.throws(
    () =>
      planRetention(
        ['version.json', `apk:v284-${'a'.repeat(12)}:0`],
        `v284-${'a'.repeat(12)}`,
      ),
    /manifest is missing/,
  );
});

test('fails closed when the version pointer is missing', () => {
  assert.throws(
    () =>
      planRetention(
        [...release(284, 'a'.repeat(12))],
        `v284-${'a'.repeat(12)}`,
      ),
    /version\.json is missing/,
  );
});

test('a single current release is already clean', () => {
  const keys = ['version.json', ...release(284, 'a'.repeat(12))];
  const plan = planRetention(keys, `v284-${'a'.repeat(12)}`);
  assert.deepEqual(plan.deleteKeys, []);
});
