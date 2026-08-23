/** Cloudflare Worker entry: serves /download from R2, redirects to the
 * visitor's locale from the bare paths, then defers to TanStack Start. */
import handler from "@tanstack/react-start/server-entry";
import { handleDownloadRequest, type DownloadEnv } from "./download";
import {
  languages,
  organizationInfo,
  pagePath,
  preferredLanguage,
  siteUrl,
  type PageKind,
} from "./i18n";
import { releases } from "./data/releases";

const SITEMAP_CACHE = "public, max-age=3600";
const ROBOTS_CACHE = "public, max-age=3600";
const LLMS_CACHE = "public, max-age=3600";

/** All page kinds that appear in the sitemap and have localized routes. */
const pageKinds: readonly PageKind[] = [
  "home",
  "changelog",
  "about",
  "contact",
  "privacy",
];

/** English-path lookup for the x-default hreflang alternate in the sitemap. */
const englishPathForKind: Record<PageKind, string> = {
  home: "/",
  changelog: "/changelog",
  about: "/about",
  contact: "/contact",
  privacy: "/privacy",
};

/** Set of every valid localized HTML page path, for the soft-404 guard. */
const validPagePaths = new Set(
  languages.flatMap((lang) =>
    pageKinds.map((kind) => pagePath(kind, lang)),
  ),
);

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
      pageKinds.map((kind: PageKind) => {
        const loc = `${siteUrl}${pagePath(kind, language)}`;
        const alternates = languages
          .map((candidate) => {
            const href = `${siteUrl}${pagePath(kind, candidate)}`;
            return `    <xhtml:link rel="alternate" hreflang="${candidate}" href="${href}"/>`;
          })
          .join("\n");
        const xDefault = `    <xhtml:link rel="alternate" hreflang="x-default" href="${siteUrl}${englishPathForKind[kind]}"/>`;
        const priority = kind === "home" ? "1.0" : kind === "changelog" ? "0.6" : "0.4";
        return `  <url>\n    <loc>${loc}</loc>\n${alternates}\n${xDefault}\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>${priority}</priority>\n  </url>`;
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
  const urls = pageKinds
    .map(
      (kind: PageKind) => {
        const priority = kind === "home" ? "1.0" : kind === "changelog" ? "0.6" : "0.4";
        return `  <url>\n    <loc>${siteUrl}${pagePath(kind, "ko")}</loc>\n    <lastmod>${lastmod}</lastmod>\n    <changefreq>weekly</changefreq>\n    <priority>${priority}</priority>\n  </url>`;
      },
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

/**
 * llms.txt — a concise, agent-readable summary of what Pulse is, when to use
 * it, and where to find things. Follows the llmstxt.org convention. Served at
 * /llms.txt and also used as the markdown response for Accept negotiation.
 */
function siteMarkdown(): string {
  return [
    `# Pulse`,
    ``,
    `> Glanceable market data for the macOS menu bar — prices, trends, and position P&L without leaving what you're doing. Made by ${organizationInfo.legalName}.`,
    ``,
    `## When to use this`,
    ``,
    `Use Pulse when an agent or user wants to:`,
    ``,
    `- Check stock, crypto, or precious-metal prices quickly from a Mac menu bar`,
    `- Track watchlists across US, Hong Kong, China A-shares, Japan, Korea, crypto, precious metals, indices, and ETFs`,
    `- Monitor position P&L (quantity, cost basis, daily and total P&L)`,
    `- View candlestick charts and extended-hours data`,
    `- Keep market data glanceable without opening a full trading terminal`,
    ``,
    `Pulse is NOT a trading terminal — there is no order placement, no execution, no broker connection for trading. It is for watching, not trading.`,
    ``,
    `## Platforms`,
    ``,
    `- macOS menu bar app (MenuBarExtra): download from ${siteUrl}/download`,
    `- Omarchy Quattro plugin (Quickshell): \`omarchy plugin add https://github.com/fatwang2/omarchy-pulse.git --enable\``,
    `- More platforms may follow.`,
    ``,
    `## Key features`,
    ``,
    `- Menu bar ticker: icon-only, pinned single symbol, or carousel`,
    `- Multi-list watchlists with drag-and-drop reordering`,
    `- Position tracking: quantity, cost basis, market value, daily P&L, total P&L`,
    `- Quote detail: price, change, OHLC, volume, amplitude, realtime/delayed status`,
    `- Charts: intraday lines and daily/weekly/monthly candlesticks`,
    `- Sharing: branded mobile-friendly image or structured market snapshot for LLM analysis`,
    `- Multi-provider data layer with automatic failover`,
    `- Real-time crypto via Binance (1-second WebSocket)`,
    `- Optional real-time via Longbridge (HK/US/A-share, push streaming)`,
    `- Session-aware per-source refresh`,
    `- Languages: English, Simplified Chinese, Japanese, Korean`,
    ``,
    `## Pricing`,
    ``,
    `Free and open source (MIT license).`,
    ``,
    `## Data sources`,
    ``,
    `Crypto: Binance public Spot API. Precious metals: Tencent, Sina, Yahoo, Shanghai Gold Exchange, Eastmoney. Securities: Yahoo, Tencent, Naver (Korea), optionally Longbridge OpenAPI for real-time push. All data is for reference only and is not investment advice.`,
    ``,
    `## Privacy`,
    ``,
    `Anonymous usage analytics via TelemetryDeck (opt-out in Settings). No watched symbols, positions, credentials, or personal data are sent. Full policy at ${siteUrl}/privacy.`,
    ``,
    `## Links`,
    ``,
    `- Website: ${siteUrl}/`,
    `- Download: ${siteUrl}/download`,
    `- Changelog: ${siteUrl}/changelog`,
    `- About: ${siteUrl}/about`,
    `- Contact: ${siteUrl}/contact`,
    `- Privacy: ${siteUrl}/privacy`,
    `- GitHub: https://github.com/fatwang2/Pulse`,
    `- Omarchy plugin: https://github.com/fatwang2/omarchy-pulse`,
    `- Sitemap: ${siteUrl}/sitemap.xml`,
  ].join("\n");
}

function handleLlmsTxtRequest(request: Request): Response | undefined {
  const url = new URL(request.url);
  if (url.pathname !== "/llms.txt") return undefined;
  return new Response(siteMarkdown(), {
    headers: {
      "content-type": "text/markdown; charset=utf-8",
      "cache-control": LLMS_CACHE,
    },
  });
}

/**
 * Markdown content negotiation (acceptmarkdown.com). When an agent sends
 * Accept: text/markdown, serve the site summary as markdown instead of the
 * HTML SPA. The Vary header tells CDNs to cache per Accept value.
 */
function handleMarkdownRequest(request: Request): Response | undefined {
  const accept = request.headers.get("accept") ?? "";
  if (!accept.includes("text/markdown")) return undefined;
  if (request.method !== "GET" && request.method !== "HEAD") return undefined;

  // Don't intercept known static-file paths — they have their own content types.
  const url = new URL(request.url);
  const staticPaths = new Set([
    "/sitemap.xml",
    "/sitemap-ko.xml",
    "/robots.txt",
    "/feed.xml",
    "/llms.txt",
    "/download",
  ]);
  if (staticPaths.has(url.pathname)) return undefined;

  return new Response(request.method === "HEAD" ? null : siteMarkdown(), {
    status: 200,
    headers: {
      "content-type": "text/markdown; charset=utf-8",
      "cache-control": LLMS_CACHE,
      vary: "Accept, Accept-Encoding",
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
 * The bare paths (`/`, `/changelog`, `/about`, `/contact`, `/privacy`) default
 * to English. When the visitor's cookie or Accept-Language says they prefer zh,
 * ja, or ko, redirect them to the localized path instead; English stays at the
 * root.
 */
function handleLanguageRedirect(request: Request): Response | undefined {
  const url = new URL(request.url);
  const normalized =
    url.pathname.length > 1 ? url.pathname.replace(/\/+$/, "") : url.pathname;

  const barePaths: Record<string, PageKind> = {
    "/": "home",
    "/changelog": "changelog",
    "/about": "about",
    "/contact": "contact",
    "/privacy": "privacy",
  };
  const page = barePaths[normalized];
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
      location: pagePath(page, preferred),
    },
  });
}

/**
 * Agent-friendly 404 guard. For HTML page requests, redirect /en/* to the bare
 * English paths, pass known localized paths through to TanStack Start, and
 * return a real HTTP 404 (with a short markdown body) for everything else — so
 * agents never mistake a soft-404 app-shell 200 for a real page.
 */
function handleNotFound(request: Request): Response | undefined {
  if (request.method !== "GET" && request.method !== "HEAD") return undefined;
  const accept = request.headers.get("accept") ?? "";
  if (!accept.includes("text/html")) return undefined;

  const url = new URL(request.url);
  const normalized =
    url.pathname.length > 1 ? url.pathname.replace(/\/+$/, "") : url.pathname;

  // Redirect /en and /en/* to the bare English paths (English has no prefix).
  if (normalized === "/en") {
    return new Response(null, {
      status: 302,
      headers: { "cache-control": "no-store", location: "/" },
    });
  }
  if (normalized.startsWith("/en/")) {
    const bare = normalized.slice(3);
    return new Response(null, {
      status: 302,
      headers: { "cache-control": "no-store", location: bare === "" ? "/" : bare },
    });
  }

  // Known localized or English page paths pass through to TanStack Start.
  if (validPagePaths.has(normalized)) return undefined;

  // Unknown path → real 404 with a markdown body pointing at the sitemap.
  const body = [
    `# 404 — Not Found`,
    ``,
    `This page does not exist on pulseticker.app.`,
    ``,
    `## Try one of these instead`,
    ``,
    `- Home: ${siteUrl}/`,
    `- Changelog: ${siteUrl}/changelog`,
    `- About: ${siteUrl}/about`,
    `- Contact: ${siteUrl}/contact`,
    `- Privacy: ${siteUrl}/privacy`,
    `- Download: ${siteUrl}/download`,
    `- Sitemap: ${siteUrl}/sitemap.xml`,
    `- llms.txt: ${siteUrl}/llms.txt`,
  ].join("\n");

  return new Response(request.method === "HEAD" ? null : body, {
    status: 404,
    headers: {
      "content-type": "text/markdown; charset=utf-8",
      "cache-control": "no-store",
      vary: "Accept",
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

    const llmsTxt = handleLlmsTxtRequest(request);
    if (llmsTxt) {
      return llmsTxt;
    }

    const markdown = handleMarkdownRequest(request);
    if (markdown) {
      return markdown;
    }

    const download = await handleDownloadRequest(request, env);
    if (download) {
      return download;
    }

    const languageRedirect = handleLanguageRedirect(request);
    if (languageRedirect) {
      return languageRedirect;
    }

    const notFound = handleNotFound(request);
    if (notFound) {
      return notFound;
    }

    const response = await startFetch(request, env, ctx);

    // Add Vary so CDNs cache the HTML and markdown variants separately
    // (acceptmarkdown.com content negotiation).
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.includes("text/html") || contentType.includes("text/markdown")) {
      response.headers.set("vary", "Accept, Accept-Encoding");
    }

    return response;
  },
};
