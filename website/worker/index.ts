/** Cloudflare Worker entry point for the vinext-starter template. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import handler from "vinext/server/app-router-entry";

const latestDownload = {
  version: "0.5.1",
  fileName: "Pulse-0.5.1.dmg",
  key: "releases/v0.5.1/Pulse-0.5.1.dmg",
  sourceUrl:
    "https://github.com/fatwang2/Pulse/releases/download/v0.5.1/Pulse-0.5.1.dmg",
  size: 5_647_513,
  sha256: "5aab61807f9c8462b50b6c4cbeff6f143d3766aaaeb33089e9e1600f3e6c9379",
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

interface Env {
  ASSETS: Fetcher;
  DB: D1Database;
  DOWNLOADS: DownloadBucket;
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
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
      "user-agent": "Pulse-Sites-Release-Mirror/1.0",
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

async function serveDownload(request: Request, env: Env): Promise<Response> {
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

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (
      url.pathname === "/download" &&
      (request.method === "GET" || request.method === "HEAD")
    ) {
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

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      return handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
    }

    return handler.fetch(request, env, ctx);
  },
};

export default worker;
