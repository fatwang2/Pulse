/** Cloudflare Worker entry: serves /download from R2, then defers to TanStack Start. */
import handler from "@tanstack/react-start/server-entry";
import { handleDownloadRequest, type DownloadEnv } from "./download";

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

    return startFetch(request, env, ctx);
  },
};
