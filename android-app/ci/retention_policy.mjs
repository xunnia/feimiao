#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const LEGACY_KEYS = new Set([
  'apk:0',
  'apk:1',
  'apk:2',
  'apk:3',
  'apk:4',
  'apk:manifest',
]);

const VERSIONED_KEY = /^apk:(v(\d+)-([0-9a-f]{12})):(manifest|\d+)$/;

/**
 * Plan retention for the update KV namespace without touching the network.
 *
 * The active version pointer is authoritative: keep it plus the newest
 * complete-looking release below it, and delete older release keys and the
 * legacy unversioned keys. Unknown keys fail closed so another KV workload
 * can never be deleted by the update cleanup.
 */
export function planRetention(
  keyNames,
  currentReleaseId,
  { keepReleases = 2 } = {},
) {
  if (!Array.isArray(keyNames)) {
    throw new Error('KV key list must be an array');
  }
  if (!Number.isSafeInteger(keepReleases) || keepReleases < 1) {
    throw new Error('keepReleases must be a positive integer');
  }
  if (!/^v\d+-[0-9a-f]{12}$/.test(currentReleaseId)) {
    throw new Error(`invalid current releaseId: ${String(currentReleaseId)}`);
  }

  const names = [...new Set(keyNames.map((value) => String(value)))];
  if (!names.includes('version.json')) {
    throw new Error('version.json is missing from KV');
  }
  const unknown = names.filter(
    (name) => name !== 'version.json' && !LEGACY_KEYS.has(name) && !VERSIONED_KEY.test(name),
  );
  if (unknown.length > 0) {
    throw new Error(`unknown KV keys: ${unknown.join(', ')}`);
  }

  const releases = new Map();
  for (const name of names) {
    const match = VERSIONED_KEY.exec(name);
    if (!match) continue;
    const [, releaseId, versionCodeText, , suffix] = match;
    const release = releases.get(releaseId) ?? {
      releaseId,
      versionCode: Number(versionCodeText),
      keys: [],
      hasManifest: false,
    };
    release.keys.push(name);
    if (suffix === 'manifest') release.hasManifest = true;
    releases.set(releaseId, release);
  }

  const current = releases.get(currentReleaseId);
  if (!current) {
    throw new Error(`current release is missing from KV: ${currentReleaseId}`);
  }
  if (!current.hasManifest) {
    throw new Error(`current release manifest is missing: ${currentReleaseId}`);
  }

  const ordered = [...releases.values()].sort(
    (left, right) =>
      right.versionCode - left.versionCode ||
      right.releaseId.localeCompare(left.releaseId),
  );
  const newerReleases = ordered.filter(
    (release) => release.versionCode > current.versionCode,
  );
  if (newerReleases.length > 0) {
    throw new Error(
      `newer release keys exist while pointer is ${currentReleaseId}: ` +
        newerReleases.map((release) => release.releaseId).join(', '),
    );
  }
  const previousCandidates = ordered.filter(
    (release) =>
      release.releaseId !== currentReleaseId &&
      release.versionCode <= current.versionCode &&
      release.hasManifest,
  );
  const keepReleaseIds = [
    currentReleaseId,
    ...previousCandidates.map((release) => release.releaseId),
  ].slice(0, keepReleases);
  const keepSet = new Set(keepReleaseIds);
  const keepKeys = names.filter((name) => {
    if (name === 'version.json') return true;
    const match = VERSIONED_KEY.exec(name);
    return match !== null && keepSet.has(match[1]);
  });
  const deleteKeys = names.filter((name) => !keepKeys.includes(name));

  return {
    currentReleaseId,
    keepReleaseIds,
    keepKeys,
    deleteKeys,
  };
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === '--assert-clean') {
      if (args.has(key)) throw new Error(`duplicate argument: ${key}`);
      args.set(key, true);
      continue;
    }
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined || args.has(key)) {
      throw new Error(
        'usage: retention_policy.mjs --keys <json> --current-release <id> ' +
          '[--keep <count>] [--assert-clean]',
      );
    }
    args.set(key, value);
    index += 1;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const keysPath = args.get('--keys');
  const currentReleaseId = args.get('--current-release');
  if (!keysPath || !currentReleaseId) {
    throw new Error('--keys and --current-release are required');
  }
  const raw = JSON.parse(await readFile(keysPath, 'utf8'));
  const keyNames = Array.isArray(raw)
    ? raw.map((entry) => (entry && typeof entry === 'object' ? entry.name : entry))
    : raw?.keys;
  const plan = planRetention(keyNames, currentReleaseId, {
    keepReleases: Number(args.get('--keep') ?? 2),
  });
  if (args.has('--assert-clean') && plan.deleteKeys.length > 0) {
    throw new Error(`retention is not clean: ${plan.deleteKeys.join(', ')}`);
  }
  process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
}

const entrypoint = process.argv[1];
if (entrypoint && import.meta.url === pathToFileURL(entrypoint).href) {
  main().catch((error) => {
    console.error(`retention policy failed: ${error.message}`);
    process.exitCode = 1;
  });
}
