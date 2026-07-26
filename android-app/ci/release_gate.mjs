#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export const RELEASE_IDENTITY_FIELDS = [
  'versionCode',
  'versionName',
  'sha256',
  'releaseId',
];

export function validateReleaseIdentity(value, label = 'release identity') {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be a JSON object`);
  }

  const { versionCode, versionName, sha256, releaseId } = value;
  if (!Number.isSafeInteger(versionCode) || versionCode <= 0) {
    throw new Error(`${label}.versionCode must be a positive integer`);
  }
  if (
    typeof versionName !== 'string' ||
    !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(versionName)
  ) {
    throw new Error(`${label}.versionName must be a canonical semantic version`);
  }
  if (typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256)) {
    throw new Error(`${label}.sha256 must be 64 lowercase hexadecimal characters`);
  }

  const expectedReleaseId = `v${versionCode}-${sha256.slice(0, 12)}`;
  if (releaseId !== expectedReleaseId) {
    throw new Error(
      `${label}.releaseId must be ${expectedReleaseId}, received ${String(releaseId)}`,
    );
  }

  return { versionCode, versionName, sha256, releaseId };
}

export function evaluateRelease(candidateValue, currentValue) {
  const candidate = validateReleaseIdentity(candidateValue, 'candidate');
  const current = validateReleaseIdentity(currentValue, 'current');

  if (candidate.versionCode > current.versionCode) {
    return { decision: 'advance', candidate, current };
  }
  if (candidate.versionCode < current.versionCode) {
    throw new Error(
      `candidate versionCode ${candidate.versionCode} is lower than current ${current.versionCode}`,
    );
  }

  const mismatches = RELEASE_IDENTITY_FIELDS.filter(
    (field) => candidate[field] !== current[field],
  );
  if (mismatches.length > 0) {
    throw new Error(
      `versionCode ${candidate.versionCode} already exists with different identity fields: ${mismatches.join(', ')}`,
    );
  }

  return { decision: 'idempotent', candidate, current };
}

export async function sha256File(path) {
  const bytes = await readFile(path);
  return createHash('sha256').update(bytes).digest('hex');
}

async function readIdentity(path, label) {
  let parsed;
  try {
    parsed = JSON.parse(await readFile(path, 'utf8'));
  } catch (error) {
    throw new Error(`${label} is not valid JSON: ${error.message}`);
  }
  return validateReleaseIdentity(parsed, label);
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) {
      throw new Error(
        'usage: release_gate.mjs --candidate <json> [--current <json>] ' +
          '[--candidate-apk <apk>] [--current-apk <apk>]',
      );
    }
    if (args.has(key)) {
      throw new Error(`duplicate argument: ${key}`);
    }
    args.set(key, value);
  }
  return args;
}

async function assertApkHash(path, identity, label) {
  const actual = await sha256File(path);
  if (actual !== identity.sha256) {
    throw new Error(
      `${label} SHA-256 ${actual} does not match identity ${identity.sha256}`,
    );
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const candidatePath = args.get('--candidate');
  if (!candidatePath) {
    throw new Error('--candidate is required');
  }

  const candidate = await readIdentity(candidatePath, 'candidate');
  const candidateApk = args.get('--candidate-apk');
  if (candidateApk) {
    await assertApkHash(candidateApk, candidate, 'candidate APK');
  }

  const currentPath = args.get('--current');
  if (!currentPath) {
    if (args.has('--current-apk')) {
      throw new Error('--current-apk requires --current');
    }
    process.stdout.write('validated\n');
    return;
  }

  const current = await readIdentity(currentPath, 'current');
  const currentApk = args.get('--current-apk');
  if (currentApk) {
    await assertApkHash(currentApk, current, 'current APK');
  }

  const result = evaluateRelease(candidate, current);
  process.stdout.write(`${result.decision}\n`);
}

const entrypoint = process.argv[1];
if (entrypoint && import.meta.url === pathToFileURL(entrypoint).href) {
  main().catch((error) => {
    console.error(`release gate failed: ${error.message}`);
    process.exitCode = 1;
  });
}
