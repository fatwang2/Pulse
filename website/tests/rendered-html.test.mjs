import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const publishedDownloadVersion = "0.10.2";

async function loadWorker(tag) {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set(tag, `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  return worker;
}

async function render(path = "/") {
  const worker = await loadWorker("test");

  return worker.fetch(
    new Request(new URL(path, "http://localhost/"), {
      headers: { accept: "text/html" },
    }),
    {},
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Pulse landing page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Pulse — Your market, at a glance<\/title>/i);
  assert.match(html, /macOS menu bar market tracker/);
  assert.match(html, /Your market,/);
  assert.match(html, /data-testid="interactive-preview"/);
  assert.match(html, /Ondas Inc\./);
  assert.match(html, /NVIDIA Corp\./);
  // The server renders the English locale, which only shows symbols with
  // English names: no A-share or Hong Kong listings.
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
  assert.match(html, /aria-pressed="false"[^>]*>中文<\/button>/);
  assert.match(html, /aria-pressed="true"[^>]*>EN<\/button>/);
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
  assert.match(html, /id="v0-10-2"/);
  assert.match(html, /href="#v0-10-2"/);
  assert.match(html, /id="v0-1-0"/);
  assert.match(html, /href="#v0-1-0"/);
  assert.ok(html.indexOf("0.10.2") < html.indexOf("0.1.0"));
  assert.match(html, /dateTime="2026-08-05"/);
  assert.match(html, /href="\/"/);
  assert.match(html, /href="\/download"/);
  assert.match(html, /github\.com\/fatwang2\/Pulse\/releases/);
  assert.doesNotMatch(html, /github\.com\/fatwang2\/Pulse\/releases\/tag\//);
  assert.doesNotMatch(html, /class="release-link"/);

  const releaseEntries = html.match(/class="release-entry"/g) ?? [];
  assert.equal(releaseEntries.length, 24);
});

test("includes English copy and remembered language selection", async () => {
  const page = await readFile(
    new URL("../src/routes/index.tsx", import.meta.url),
    "utf8",
  );

  assert.match(page, /Your market,/);
  assert.match(page, /macOS menu bar market tracker/);
  assert.match(page, /Download for macOS/);
  assert.match(page, /View on GitHub/);
  assert.match(page, /navigator\.language/);
  assert.match(page, /localStorage\.getItem\("pulse-language"\)/);
  assert.match(page, /localStorage\.setItem\("pulse-language", nextLanguage\)/);
  assert.doesNotMatch(page, /viewRelease/);
  assert.match(page, /document\.documentElement\.lang/);
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

test("changelog shares the remembered language selection", async () => {
  const page = await readFile(
    new URL("../src/routes/changelog.tsx", import.meta.url),
    "utf8",
  );
  const releaseData = await readFile(
    new URL("../src/data/releases.ts", import.meta.url),
    "utf8",
  );

  assert.match(page, /Every release,/);
  assert.match(page, /每一次更新/);
  assert.match(page, /localStorage\.getItem\("pulse-language"\)/);
  assert.match(page, /localStorage\.setItem\("pulse-language", nextLanguage\)/);
  assert.match(releaseData, /version: "0\.8\.0"/);
  assert.match(releaseData, /version: "0\.1\.0"/);
  assert.match(releaseData, /Longbridge 行情切换/);
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
