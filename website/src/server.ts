/** Cloudflare Worker entry: serves /download from R2, redirects to the
 * visitor's locale from the bare paths, then defers to TanStack Start. */
import handler from "@tanstack/react-start/server-entry";
import { handleDownloadRequest, type DownloadEnv } from "./download";
import {
  changelogPath,
  homePath,
  preferredLanguage,
} from "./i18n";

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// The stock server entry forwards the Workers runtime arguments verbatim, but
// its published type only declares (request, opts?). Keep the runtime behavior.
const startFetch = handler.fetch as (
  request: Request,
  env: DownloadEnv,
  ctx: ExecutionContext,
) => Promise<Response> | Response;

/**
 * The bare `/` and `/changelog` paths default to English. When the visitor's
 * cookie or Accept-Language says they prefer zh or ja, redirect them to the
 * localized path instead; English stays at the root.
 */
function handleLanguageRedirect(request: Request): Response | undefined {
  const url = new URL(request.url);
  const normalized =
    url.pathname.length > 1 ? url.pathname.replace(/\/+$/, "") : url.pathname;
  const page =
    normalized === "/"
      ? "home"
      : normalized === "/changelog"
        ? "changelog"
        : undefined;
  if (!page) return undefined;
  if (request.method !== "GET" && request.method !== "HEAD") return undefined;
  if (!(request.headers.get("accept") ?? "").includes("text/html")) {
    return undefined;
  }

  const preferred = preferredLanguage(
    request.headers.get("cookie"),
    request.headers.get("accept-language"),
  );
  if (!preferred || preferred === "en") return undefined;

  return new Response(null, {
    status: 302,
    headers: {
      "cache-control": "no-store",
      location: page === "home" ? homePath(preferred) : changelogPath(preferred),
    },
  });
}

export default {
  async fetch(
    request: Request,
    env: DownloadEnv,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const download = await handleDownloadRequest(request, env);
    if (download) {
      return download;
    }

    const languageRedirect = handleLanguageRedirect(request);
    if (languageRedirect) {
      return languageRedirect;
    }

    return startFetch(request, env, ctx);
  },
};
