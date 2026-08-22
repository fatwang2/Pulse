/** Cloudflare Worker entry: serves /download from R2, redirects to the
 * visitor's locale from the bare paths, then defers to TanStack Start. */
import handler from "@tanstack/react-start/server-entry";
import { handleDownloadRequest, type DownloadEnv } from "./download";
import {
  changelogPath,
  homePath,
  languages,
  pagePath,
  preferredLanguage,
  siteUrl,
  type PageKind,
} from "./i18n";
import { releases } from "./data/releases";

const SITEMAP_CACHE = "public, max-age=3600";
const ROBOTS_CACHE = "public, max-age=3600";

/** Escape text for safe inclusion in XML node bodies or attributes. */
function escapeXml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/**
 * XML sitemap covering every public URL, mirroring the canonical/hreflang
 * set in i18n.ts. Each entry carries xhtml:link alternates so Google can
 * consolidate the locale variants. Served by the Worker so it never falls
 * through to the SPA catch-all (which would 302 to the homepage).
 */
function sitemapXml(): string {
  const lastmod = releases[0]?.date ?? new Date().toISOString().slice(0, 10);
  const urls = languages
    .flatMap((language: (typeof languages)[number]) =>
      (["home", "changelog"] as const).map((kind: PageKind) => {
        const loc = `${siteUrl}${pagePath(kind, language)}`;
        const alternates = languages
          .map((candidate) => {
            const href = `${siteUrl}${pagePath(kind, candidate)}`;
            return `    <xhtml:link rel="alternate" hreflang="${candidate}" href="${href}"/>`;
          })
          .join("\n");
        const xDefault = `    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}${kind === "home" ? "/" : "/changelog"}"/>`;
        return `  <url>\n    <loc>${loc}</loc>\n${alternates}\n${xDefault}\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>${kind === "home" ? "1.0" : "0.5"}</priority>\n  </url>`;
      }),
    )
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls}\n</urlset>\n`;
}

/**
 * Korean-only sitemap for Naver Search Advisor. Naver does not support
 * hreflang and recommends submitting a locale-specific sitemap so its
 * crawler (Yeti) can focus on the Korean pages.
 */
function sitemapKoXml(): string {
  const lastmod = releases[0]?.date ?? new Date().toISOString().slice(0, 10);
  const urls = (["home", "changelog"] as const)
    .map(
      (kind: PageKind) =>
        `  <url>\n    <loc>${siteUrl}${pagePath(kind, "ko")}</loc>\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>${kind === "home" ? "1.0" : "0.5"}</priority>\n  </url>`,
    )
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`;
}

/**
 * Atom feed of recent releases, primarily for Naver Search Advisor which
 * requires both an XML sitemap and an RSS/Atom feed. Also useful for
 * general feed readers.
 */
function atomFeedXml(): string {
  const updated =
    releases[0]?.date ?? new Date().toISOString().slice(0, 10);
  const entries = releases
    .slice(0, 10)
    .map((release) => {
      const highlights = release.highlights.en.join(" ");
      const anchor = `${siteUrl}/changelog#${release.version}`;
      return `  <entry>\n    <title>Pulse ${release.version}</title>\n    <link href="${anchor}"/>\n    <id>${anchor}</id>\n    <updated>${release.date}T00:00:00Z</updated>\n    <summary>${escapeXml(highlights)}</summary>\n  </entry>`;
    })
    .join("\n");
  return `<?xml version="1.0" encoding="UTF-8"?>\n<feed xmlns="http://www.w3.org/2005/Atom">\n  <title>Pulse Changelog</title>\n  <link href="${siteUrl}/changelog"/>\n  <link rel="self" href="${siteUrl}/feed.xml"/>\n  <id>${siteUrl}/changelog</id>\n  <updated>${updated}T00:00:00Z</updated>\n  <author><name>Pulse</name></author>\n${entries}\n</feed>\n`;
}

/**
 * Self-hosted robots.txt. Replaces the Cloudflare managed default, which
 * disallows GPTBot / ClaudeBot / CCBot / Bytespider / Google-Extended /
 * Applebot-Extended and therefore blocks AI search engines from citing the
 * site. We keep training off but allow indexing/reference for AI answers.
 */
function robotsTxt(): string {
  const aiCrawlers = [
    "GPTBot",
    "ClaudeBot",
    "Claude-Web",
    "CCBot",
    "Bytespider",
    "Google-Extended",
    "PerplexityBot",
    "Applebot-Extended",
    "OAI-SearchBot",
  ];
  return [
    "User-agent: *",
    "Allow: /",
    "Content-Signal: search=yes, ai-train=no, use=reference",
    "",
    "# Naver's crawler. Explicitly allowed so Yeti never falls through to a",
    "# restrictive default on a site that only names Googlebot / Bingbot.",
    "User-agent: Yeti",
    "Allow: /",
    "",
    "# AI crawlers: allowed to index and reference content for AI search",
    "# answers, but not to train on it.",
    ...aiCrawlers.flatMap((crawler) => [
      `User-agent: ${crawler}`,
      "Allow: /",
      "",
    ]),
    `Sitemap: ${siteUrl}/sitemap.xml`,
    `Sitemap: ${siteUrl}/sitemap-ko.xml`,
    "",
  ].join("\n");
}

function handleSitemapRequest(request: Request): Response | undefined {
  const url = new URL(request.url);
  if (url.pathname !== "/sitemap.xml") return undefined;
  return new Response(sitemapXml(), {
    headers: {
      "content-type": "application/xml; charset=utf-8",
      "cache-control": SITEMAP_CACHE,
    },
  });
}

function handleRobotsRequest(request: Request): Response | undefined {
  const url = new URL(request.url);
  if (url.pathname !== "/robots.txt") return undefined;
  return new Response(robotsTxt(), {
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": ROBOTS_CACHE,
    },
  });
}

function handleFeedRequest(request: Request): Response | undefined {
  const url = new URL(request.url);
  if (url.pathname !== "/feed.xml") return undefined;
  return new Response(atomFeedXml(), {
    headers: {
      "content-type": "application/atom+xml; charset=utf-8",
      "cache-control": SITEMAP_CACHE,
    },
  });
}

function handleSitemapKoRequest(request: Request): Response | undefined {
  const url = new URL(request.url);
  if (url.pathname !== "/sitemap-ko.xml") return undefined;
  return new Response(sitemapKoXml(), {
    headers: {
      "content-type": "application/xml; charset=utf-8",
      "cache-control": SITEMAP_CACHE,
    },
  });
}

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
    const sitemap = handleSitemapRequest(request);
    if (sitemap) {
      return sitemap;
    }

    const robots = handleRobotsRequest(request);
    if (robots) {
      return robots;
    }

    const feed = handleFeedRequest(request);
    if (feed) {
      return feed;
    }

    const sitemapKo = handleSitemapKoRequest(request);
    if (sitemapKo) {
      return sitemapKo;
    }

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
