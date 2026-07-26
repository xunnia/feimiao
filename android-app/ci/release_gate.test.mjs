import assert from 'node:assert/strict';
import { test } from 'node:test';

import { evaluateRelease, validateReleaseIdentity } from './release_gate.mjs';

const shaA = 'a'.repeat(64);
const shaB = 'b'.repeat(64);

function identity({
  versionCode = 198,
  versionName = '1.196.0',
  sha256 = shaA,
  releaseId = `v${versionCode}-${sha256.slice(0, 12)}`,
} = {}) {
  return { versionCode, versionName, sha256, releaseId };
}

test('allows a strictly higher versionCode', () => {
  const result = evaluateRelease(
    identity({ versionCode: 199, versionName: '1.197.0', sha256: shaB }),
    identity(),
  );
  assert.equal(result.decision, 'advance');
});

test('treats the same version and exact identity as idempotent', () => {
  assert.equal(evaluateRelease(identity(), identity()).decision, 'idempotent');
});

test('rejects a lower versionCode', () => {
  assert.throws(
    () => evaluateRelease(identity({ versionCode: 197 }), identity()),
    /lower than current/,
  );
});

test('rejects the same versionCode with a different versionName', () => {
  assert.throws(
    () => evaluateRelease(identity({ versionName: '1.196.1' }), identity()),
    /versionName/,
  );
});

test('rejects the same versionCode with a different SHA-256', () => {
  assert.throws(
    () => evaluateRelease(identity({ sha256: shaB }), identity()),
    /sha256|releaseId/,
  );
});

test('rejects a releaseId that is not derived from versionCode and SHA-256', () => {
  assert.throws(
    () => validateReleaseIdentity(identity({ releaseId: 'v198-deadbeefdead' })),
    /releaseId must be/,
  );
});

test('rejects non-canonical SHA-256 text', () => {
  assert.throws(
    () => validateReleaseIdentity(identity({ sha256: shaA.toUpperCase() })),
    /lowercase hexadecimal/,
  );
});

test('rejects a zero or non-integer versionCode', () => {
  assert.throws(
    () => validateReleaseIdentity(identity({ versionCode: 0 })),
    /positive integer/,
  );
  assert.throws(
    () =>
      validateReleaseIdentity({
        ...identity(),
        versionCode: 198.5,
      }),
    /positive integer/,
  );
});

test('rejects whitespace and non-canonical version names', () => {
  assert.throws(
    () => validateReleaseIdentity(identity({ versionName: ' 1.196.0 ' })),
    /canonical semantic version/,
  );
  assert.throws(
    () => validateReleaseIdentity(identity({ versionName: 'latest' })),
    /canonical semantic version/,
  );
});
