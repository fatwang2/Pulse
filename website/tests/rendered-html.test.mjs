import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const publishedDownloadVersion = "0.11.0";

async function loadWorker(tag) {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set(tag, `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker;
}

async function render(path = "/", headers = {}) {
  const worker = await loadWorker("test");

  return worker.fetch(
    new Request(new URL(path, "http://localhost/"), {
      headers: { accept: "text/html", ...headers },
    }),
    {},
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the English landing page at the root", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>Pulse — Your market, at a glance<\/title>/i);
  assert.match(html, /macOS menu bar market tracker/);
  assert.match(html, /Your market,/);
  assert.match(html, /data-testid="interactive-preview"/);
  assert.match(html, /Ondas Inc\./);
  assert.match(html, /NVIDIA Corp\./);
  // The English page only shows symbols with English names: no A-share or
  // Hong Kong listings.
  assert.doesNotMatch(html, /工业富联/);
  assert.doesNotMatch(html, /腾讯控股/);
  assert.match(html, /class="market-pulse" aria-hidden="true"/);
  assert.match(html, /class="brand-mark"/);
  assert.match(html, /href="\/download"/);
  assert.match(html, /href="\/changelog"/);
  assert.doesNotMatch(html, /github\.com\/fatwang2\/Pulse\/releases\/latest/);
  assert.match(html, /apple\.svg/);
  assert.match(html, /Market data sources/);
  assert.match(html, /providers\/longbridge\.png/);
  assert.match(html, /providers\/binance\.svg/);
  assert.match(html, /providers\/tencent\.png/);
  assert.match(html, /providers\/yahoo-finance\.svg/);
  // The language switcher is a set of links now; EN is the active locale at
  // the root, zh and ja point at their prefixed paths.
  assert.match(html, /href="\/zh"[^>]*>中文<\/a>/);
  assert.match(html, /aria-current="page"[^>]*>EN<\/a>/);
  assert.match(html, /href="\/ja"[^>]*>日本語<\/a>/);
});

test("server-renders the feature showcase and release link", async () => {
  const response = await render();
  const html = await response.text();

  assert.match(html, /Multi-list watchlists/);
  assert.match(html, /data-testid="feature-showcase"/);
  assert.match(html, /data-testid="candle-demo"/);
  assert.match(html, /data-testid="extended-hours-demo"/);
  assert.match(html, /data-testid="positions-demo"/);
  assert.match(html, /data-testid="lists-demo"/);
  assert.match(html, /True candlesticks/);
  assert.match(html, /Extended hours built in/);
  assert.match(html, /Position P&amp;L at a glance/);
  assert.match(html, /Multi-list watchlists/);
  assert.match(html, /Hover for time and price/);
  assert.match(html, /Click a tab to switch lists/);
  assert.match(html, />1M<\/button>/);
  assert.doesNotMatch(html, />1Y<\/button>/);

  assert.match(html, /data-testid="preview-list-tabs"/);
  assert.match(html, /role="tab" aria-selected="true"/);

  assert.match(html, /data-testid="whats-new"/);
  assert.match(html, /class="whats-new-badge">v\d+\.\d+\.\d+</);
  assert.match(html, /View changelog/);
  assert.match(html, /Released /);
});

test("server-renders the full bilingual release timeline", async () => {
  const response = await render("/changelog");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(
    html,
    /<title>Pulse Changelog — Every release at a glance<\/title>/i,
  );
  assert.match(html, /data-testid="release-timeline"/);
  assert.match(html, /Every release,/);
  assert.match(html, /id="v0-11-0"/);
  assert.match(html, /href="#v0-11-0"/);
  assert.match(html, /id="v0-1-0"/);
  assert.match(html, /href="#v0-1-0"/);
  assert.ok(html.indexOf("0.11.0") < html.indexOf("0.1.0"));
  assert.match(html, /dateTime="2026-08-07"/);
  assert.match(html, /href="\/"/);
  assert.match(html, /href="\/download"/);
  assert.match(html, /github\.com\/fatwang2\/Pulse\/releases/);
  assert.doesNotMatch(html, /github\.com\/fatwang2\/Pulse\/releases\/tag\//);
  assert.doesNotMatch(html, /class="release-link"/);

  const releaseEntries = html.match(/class="release-entry"/g) ?? [];
  assert.equal(releaseEntries.length, 25);
});

test("serves the Chinese homepage at /zh", async () => {
  const response = await render("/zh");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /<title>Pulse — 你的市场，一眼掌握<\/title>/i);
  assert.match(html, /你的市场，/);
  assert.match(html, /腾讯控股/);
  assert.doesNotMatch(html, /NVIDIA Corp\./);
  assert.match(html, /href="\/zh\/changelog"/);
  assert.match(html, /href="\/"[^>]*>EN<\/a>/);
  assert.match(html, /下载最新版/);
  // Localized SEO: canonical + hreflang alternates.
  assert.match(
    html,
    /rel="canonical" href="https:\/\/www\.pulseticker\.app\/zh"/,
  );
  assert.match(
    html,
    /hreflang="x-default" href="https:\/\/www\.pulseticker\.app\/"/,
  );
  assert.match(html, /hreflang="ja" href="https:\/\/www\.pulseticker\.app\/ja"/);
  assert.match(
    html,
    /hreflang="en" href="https:\/\/www\.pulseticker\.app\/"/,
  );
});

test("serves the Japanese changelog at /ja/changelog", async () => {
  const response = await render("/ja/changelog");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="ja">/);
  assert.match(
    html,
    /<title>Pulse 更新履歴 — すべてのリリースをひと目で<\/title>/i,
  );
  assert.match(html, /すべてのリリースを、/);
  assert.match(html, /日本語に対応しました。/);
  assert.match(html, /href="\/ja"/);
  assert.match(
    html,
    /rel="canonical" href="https:\/\/www\.pulseticker\.app\/ja\/changelog"/,
  );
  assert.match(
    html,
    /hreflang="zh" href="https:\/\/www\.pulseticker\.app\/zh\/changelog"/,
  );
});

test("redirects zh browsers from / to the Chinese homepage", async () => {
  const response = await render("/", {
    "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "/zh");
});

test("respects the language cookie over Accept-Language", async () => {
  const response = await render("/changelog", {
    "accept-language": "en-US,en;q=0.9",
    cookie: "pulse-lang=ja",
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "/ja/changelog");
});

test("handles trailing slashes on the bare paths", async () => {
  const response = await render("/changelog/", {
    "accept-language": "zh-CN,zh;q=0.9",
  });
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "/zh/changelog");
});

test("redirects /en and /en/changelog back to the English pages", async () => {
  const home = await render("/en");
  assert.equal(home.status, 302);
  assert.equal(home.headers.get("location"), "/");

  const changelog = await render("/en/changelog");
  assert.equal(changelog.status, 302);
  assert.equal(changelog.headers.get("location"), "/changelog");
});

test("English copy lives at the root and language is a URL path", async () => {
  const homePage = await readFile(
    new URL("../src/components/home-page.tsx", import.meta.url),
    "utf8",
  );
  const i18n = await readFile(
    new URL("../src/i18n.ts", import.meta.url),
    "utf8",
  );

  assert.match(homePage, /Your market,/);
  assert.match(homePage, /macOS menu bar market tracker/);
  assert.match(homePage, /Download for macOS/);
  assert.match(homePage, /View on GitHub/);
  assert.doesNotMatch(homePage, /viewRelease/);
  // Language is a URL path now, not per-browser state.
  assert.doesNotMatch(homePage, /localStorage/);
  assert.match(i18n, /languageCookieName = "pulse-lang"/);
  assert.match(i18n, /preferredLanguage/);
  assert.match(i18n, /detectLanguageFromAcceptLanguage/);
});

test("enables GA4 analytics while keeping advertising consent disabled", async () => {
  const rootRoute = await readFile(
    new URL("../src/routes/__root.tsx", import.meta.url),
    "utf8",
  );
  const analyticsEvents = await readFile(
    new URL("../src/components/analytics-events.tsx", import.meta.url),
    "utf8",
  );

  assert.match(rootRoute, /G-J9GLF06LPP/);
  assert.match(rootRoute, /googletagmanager\.com\/gtag\/js/);
  assert.match(rootRoute, /analytics_storage: "granted"/);
  assert.match(rootRoute, /ad_storage: "denied"/);
  assert.match(rootRoute, /ad_user_data: "denied"/);
  assert.match(rootRoute, /ad_personalization: "denied"/);
  assert.match(rootRoute, /allow_google_signals", false/);
  assert.match(analyticsEvents, /"file_download"/);
  assert.match(analyticsEvents, /url\.pathname !== "\/download"/);
  assert.match(analyticsEvents, /transport_type: "beacon"/);

  const response = await render();
  const html = await response.text();
  const head = html.slice(0, html.indexOf("</head>"));
  assert.match(head, /dataLayer/);
  assert.match(head, /googletagmanager\.com\/gtag\/js/);
});

test("changelog copy ships in all three languages", async () => {
  const changelogPage = await readFile(
    new URL("../src/components/changelog-page.tsx", import.meta.url),
    "utf8",
  );
  const releaseData = await readFile(
    new URL("../src/data/releases.ts", import.meta.url),
    "utf8",
  );

  assert.match(changelogPage, /Every release,/);
  assert.match(changelogPage, /每一次更新/);
  assert.doesNotMatch(changelogPage, /localStorage/);
  assert.match(releaseData, /version: "0\.8\.0"/);
  assert.match(releaseData, /version: "0\.1\.0"/);
  assert.match(releaseData, /Longbridge 行情切换/);
  assert.match(releaseData, /ja: \[/);
  assert.match(releaseData, /正式な Pulse macOS アプリアイコンを導入しました。/);
});

test("redirects the stable download URL to a versioned request", async () => {
  const worker = await loadWorker("download-test");

  const response = await worker.fetch(
    new Request("http://localhost/download", { redirect: "manual" }),
    {},
    {},
  );

  assert.equal(response.status, 302);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(
    response.headers.get("location"),
    `http://localhost/download?version=${publishedDownloadVersion}`,
  );
});

test("serves a stored DMG from the R2 binding", async () => {
  const worker = await loadWorker("r2-test");
  const body = new TextEncoder().encode("dmg");

  const response = await worker.fetch(
    new Request(`http://localhost/download?version=${publishedDownloadVersion}`),
    {
      DOWNLOADS: {
        async get(key) {
          assert.equal(
            key,
            `releases/v${publishedDownloadVersion}/Pulse-${publishedDownloadVersion}.dmg`,
          );
          return {
            body: new Blob([body]).stream(),
            httpEtag: '"test-etag"',
            size: body.byteLength,
            writeHttpMetadata(headers) {
              headers.set("content-type", "application/x-apple-diskimage");
            },
          };
        },
      },
    },
    {},
  );

  assert.equal(response.status, 200);
  assert.equal(
    response.headers.get("content-disposition"),
    `attachment; filename="Pulse-${publishedDownloadVersion}.dmg"`,
  );
  assert.equal(
    response.headers.get("content-type"),
    "application/x-apple-diskimage",
  );
  assert.equal(
    response.headers.get("x-pulse-version"),
    publishedDownloadVersion,
  );
  assert.equal(new TextDecoder().decode(await response.arrayBuffer()), "dmg");
});
