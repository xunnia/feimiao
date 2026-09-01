// Feimiao in-app update distribution, backed by Cloudflare KV chunks.
//
// GET /version.json
//   Returns the active version metadata.
//
// GET /rollback.json
//   Returns the signed historical-build catalog.  Catalog entries carry an
//   immutable HTTPS URL and an installVersionCode; the bytes may live in this
//   worker's release chunks or in a separate archive (R2/GitHub Releases), so
//   normal KV retention does not have to keep every historical APK.
//
// GET /feimiao-latest.apk?release=<releaseId>
//   Streams apk:<releaseId>:0..N-1. The publish script writes all chunks and
//   apk:<releaseId>:manifest first, then switches version.json last, so users
//   never download a half-old / half-new APK during publishing.
//
//   Supports single-part Range requests (bytes=a-b / bytes=a- / bytes=-n):
//   Android DownloadManager resumes with Range, and MIUI's Xunlei accelerator
//   fans out multi-threaded ranged requests — answering 200-full-body to those
//   made downloads stall with "unknown size". We answer 206 + content-range.
//
//   All APK responses carry `cache-control: no-transform`: without it
//   Cloudflare re-encodes the streamed body (chunked/gzip) for clients that
//   send Accept-Encoding, which strips content-length and the download UI
//   shows "total size unknown".
//
// Backward compatibility:
//   If the current version.json was published by the old script and has no
//   releaseId, the worker falls back to apk:manifest and apk:0..N-1.

// Must equal the publish script's `split -b 24m` (24 MiB).
const CHUNK_SIZE = 24 * 1024 * 1024;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/version.json") {
      const body = await env.UPDATES.get("version.json");
      if (body === null) return new Response("not found", { status: 404 });
      return new Response(body, {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-cache",
        },
      });
    }

    if (url.pathname === "/rollback.json") {
      const body = await env.UPDATES.get("rollback.json");
      if (body === null) return new Response("not found", { status: 404 });
      return new Response(body, {
        headers: {
          "content-type": "application/json; charset=utf-8",
          // The catalog is changed atomically with a publish operation, so a
          // short cache avoids stale lists without pinning an old release.
          "cache-control": "no-cache",
        },
      });
    }

    // 诊断：某分片在当前边缘节点是否已缓存（排查下载速度用）。
    if (url.pathname === "/__chunkstat") {
      const rid = url.searchParams.get("release") ?? "legacy";
      const i = url.searchParams.get("i") ?? "0";
      const cached = await caches.default.match(chunkCacheKey(rid, i));
      return Response.json({
        colo: request.cf?.colo ?? "?",
        chunk: Number(i),
        cached: cached !== undefined,
      });
    }

    if (url.pathname === "/feimiao-latest.apk") {
      let releaseId = url.searchParams.get("release");
      if (!releaseId) {
        const versionRaw = await env.UPDATES.get("version.json");
        if (versionRaw !== null) {
          releaseId = JSON.parse(versionRaw).releaseId;
        }
      }

      const manifestKey = releaseId ? `apk:${releaseId}:manifest` : "apk:manifest";
      const manifestRaw = await env.UPDATES.get(manifestKey);
      if (manifestRaw === null) {
        return new Response("not found", { status: 404 });
      }

      const manifest = JSON.parse(manifestRaw);
      const total = manifest.size;
      const baseHeaders = {
        "x-feimiao-colo": request.cf?.colo ?? "?",
        "content-type": "application/vnd.android.package-archive",
        "accept-ranges": "bytes",
        "cache-control": "no-cache, no-transform",
        ...(manifest.sha256 ? { "x-feimiao-sha256": manifest.sha256 } : {}),
      };

      const range = parseRange(request.headers.get("range"), total);
      if (range === "invalid") {
        return new Response("range not satisfiable", {
          status: 416,
          headers: { "content-range": `bytes */${total}` },
        });
      }

      // FixedLengthStream：Workers 对普通流式响应会忽略手写 content-length
      // 转 chunked（下载器显示"总大小未知"）；声明定长流才会真发 content-length。
      if (range) {
        const { start, end } = range; // both inclusive
        const { readable, writable } = new FixedLengthStream(end - start + 1);
        pumpRange(env, ctx, releaseId, manifest, start, end, writable);
        return new Response(readable, {
          status: 206,
          headers: {
            ...baseHeaders,
            "content-range": `bytes ${start}-${end}/${total}`,
          },
        });
      }

      const { readable, writable } = new FixedLengthStream(total);
      pumpChunks(env, ctx, releaseId, manifest.chunks, writable);
      return new Response(readable, {
        headers: baseHeaders,
      });
    }

    return new Response("feimiao updates", { status: 200 });
  },
};

// Single-part ranges only; multi-part (a-b,c-d) falls back to a full 200.
// Returns null (no/ignored range), "invalid" (416), or {start, end} inclusive.
function parseRange(header, total) {
  if (!header) return null;
  const m = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!m) return null; // multi-part or malformed: serve full body
  const [, rawStart, rawEnd] = m;
  if (rawStart === "" && rawEnd === "") return null;

  let start;
  let end;
  if (rawStart === "") {
    // suffix form: last N bytes
    const n = Number(rawEnd);
    if (n === 0) return "invalid";
    start = Math.max(total - n, 0);
    end = total - 1;
  } else {
    start = Number(rawStart);
    end = rawEnd === "" ? total - 1 : Math.min(Number(rawEnd), total - 1);
  }
  if (start >= total || start > end) return "invalid";
  return { start, end };
}

async function pumpChunks(env, ctx, releaseId, count, writable) {
  const writer = writable.getWriter();
  try {
    for (let i = 0; i < count; i++) {
      const chunk = await getChunk(env, ctx, releaseId, i);
      await writer.write(new Uint8Array(chunk));
    }
    await writer.close();
  } catch (e) {
    await writer.abort(e);
  }
}

// Streams [start, end] (inclusive) by slicing only the KV chunks that overlap.
async function pumpRange(env, ctx, releaseId, manifest, start, end, writable) {
  const writer = writable.getWriter();
  try {
    const firstChunk = Math.floor(start / CHUNK_SIZE);
    const lastChunk = Math.min(
      Math.floor(end / CHUNK_SIZE),
      manifest.chunks - 1,
    );
    for (let i = firstChunk; i <= lastChunk; i++) {
      const chunk = await getChunk(env, ctx, releaseId, i);
      const chunkStart = i * CHUNK_SIZE;
      const sliceFrom = Math.max(start - chunkStart, 0);
      const sliceTo = Math.min(end + 1 - chunkStart, chunk.byteLength);
      await writer.write(new Uint8Array(chunk, sliceFrom, sliceTo - sliceFrom));
    }
    await writer.close();
  } catch (e) {
    await writer.abort(e);
  }
}

// KV 读一次 ~24MB 不便宜；迅雷/DownloadManager 的多线程分段会对同一分片
// 发几十个 Range 请求，逐次回源 KV 是当前限速主因。首次读到后写入边缘
// Cache API（按 releaseId 隔离、内容不可变），后续分段直接命中本地缓存。
function chunkCacheKey(releaseId, i) {
  return new Request(
    `https://updates.xunni9481.dpdns.org/__chunk/${encodeURIComponent(releaseId)}/${i}`,
  );
}

async function getChunk(env, ctx, releaseId, i) {
  const cacheKey = chunkCacheKey(releaseId ?? "legacy", i);
  const cache = caches.default;
  const cached = await cache.match(cacheKey);
  if (cached) return cached.arrayBuffer();

  const key = releaseId ? `apk:${releaseId}:${i}` : `apk:${i}`;
  const chunk = await env.UPDATES.get(key, "arrayBuffer");
  if (chunk === null) throw new Error(`missing chunk ${i}`);
  ctx.waitUntil(
    cache.put(
      cacheKey,
      new Response(chunk, {
        headers: { "cache-control": "public, max-age=31536000, immutable" },
      }),
    ),
  );
  return chunk;
}
