/**
 * R2-backed mirror for the latest Pulse DMG.
 *
 * When releasing a new version, update `latestDownload` (version, file name,
 * key, source URL, size, and SHA-256) to match the GitHub Release assets.
 */

export const latestDownload = {
  version: "0.10.1",
  fileName: "Pulse-0.10.1.dmg",
  key: "releases/v0.10.1/Pulse-0.10.1.dmg",
  sourceUrl:
    "https://github.com/fatwang2/Pulse/releases/download/v0.10.1/Pulse-0.10.1.dmg",
  size: 12_231_343,
  sha256: "4902d822d819107869353cd140c592dbf40e01ee8885eac81052165dc1ba8aad",
} as const;

interface DownloadObject {
  body: ReadableStream;
  httpEtag: string;
  size: number;
  writeHttpMetadata(headers: Headers): void;
}

interface DownloadBucket {
  get(key: string): Promise<DownloadObject | null>;
  put(
    key: string,
    value: ArrayBuffer,
    options: {
      httpMetadata: {
        contentType: string;
        contentDisposition: string;
        cacheControl: string;
      };
      customMetadata: Record<string, string>;
    },
  ): Promise<unknown>;
}

export interface DownloadEnv {
  DOWNLOADS: DownloadBucket;
}

function downloadHeaders(size: number, etag?: string): Headers {
  const headers = new Headers({
    "cache-control": "public, max-age=31536000, immutable",
    "content-disposition": `attachment; filename="${latestDownload.fileName}"`,
    "content-length": String(size),
    "content-type": "application/x-apple-diskimage",
    "x-content-type-options": "nosniff",
    "x-pulse-version": latestDownload.version,
    "x-pulse-sha256": latestDownload.sha256,
  });

  if (etag) {
    headers.set("etag", etag);
  }

  return headers;
}

async function sha256Hex(value: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", value);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function fetchValidatedRelease(): Promise<ArrayBuffer> {
  const response = await fetch(latestDownload.sourceUrl, {
    headers: {
      accept: "application/octet-stream",
      "user-agent": "Pulse-Website-Release-Mirror/1.0",
    },
    redirect: "follow",
  });

  if (!response.ok) {
    throw new Error(`Unable to fetch Pulse ${latestDownload.version}: ${response.status}`);
  }

  const bytes = await response.arrayBuffer();
  if (bytes.byteLength !== latestDownload.size) {
    throw new Error(
      `Pulse ${latestDownload.version} size mismatch: ${bytes.byteLength}`,
    );
  }

  const digest = await sha256Hex(bytes);
  if (digest !== latestDownload.sha256) {
    throw new Error(`Pulse ${latestDownload.version} checksum mismatch`);
  }

  return bytes;
}

async function serveDownload(request: Request, env: DownloadEnv): Promise<Response> {
  const existing = await env.DOWNLOADS.get(latestDownload.key);
  if (existing) {
    const headers = downloadHeaders(existing.size, existing.httpEtag);
    existing.writeHttpMetadata(headers);
    headers.set(
      "content-disposition",
      `attachment; filename="${latestDownload.fileName}"`,
    );
    headers.set("cache-control", "public, max-age=31536000, immutable");
    headers.set("x-content-type-options", "nosniff");
    headers.set("x-pulse-version", latestDownload.version);
    headers.set("x-pulse-sha256", latestDownload.sha256);

    return new Response(request.method === "HEAD" ? null : existing.body, {
      headers,
    });
  }

  const bytes = await fetchValidatedRelease();
  await env.DOWNLOADS.put(latestDownload.key, bytes, {
    httpMetadata: {
      contentType: "application/x-apple-diskimage",
      contentDisposition: `attachment; filename="${latestDownload.fileName}"`,
      cacheControl: "public, max-age=31536000, immutable",
    },
    customMetadata: {
      source: latestDownload.sourceUrl,
      version: latestDownload.version,
      sha256: latestDownload.sha256,
    },
  });

  return new Response(request.method === "HEAD" ? null : bytes, {
    headers: downloadHeaders(bytes.byteLength, `"${latestDownload.sha256}"`),
  });
}

/**
 * Handles `/download` requests; returns `null` for every other request so the
 * caller can fall through to the TanStack Start handler.
 */
export async function handleDownloadRequest(
  request: Request,
  env: DownloadEnv,
): Promise<Response | null> {
  const url = new URL(request.url);

  if (
    url.pathname !== "/download" ||
    (request.method !== "GET" && request.method !== "HEAD")
  ) {
    return null;
  }

  if (url.searchParams.get("version") !== latestDownload.version) {
    const versionedUrl = new URL("/download", request.url);
    versionedUrl.searchParams.set("version", latestDownload.version);
    return new Response(null, {
      status: 302,
      headers: {
        "cache-control": "no-store",
        location: versionedUrl.toString(),
      },
    });
  }

  try {
    return await serveDownload(request, env);
  } catch (error) {
    console.error("Pulse download mirror failed", error);
    return new Response("The Pulse download is temporarily unavailable.", {
      status: 503,
      headers: {
        "cache-control": "no-store",
        "content-type": "text/plain; charset=utf-8",
      },
    });
  }
}
