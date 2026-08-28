import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const publishedDownloadVersion = "0.14.0";

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
  assert.match(html, /<title>Pulse — macOS Menu Bar Stock Tracker<\/title>/i);
  assert.match(html, /lightweight macOS menu bar stock and market tracker/);
  assert.match(html, /macOS menu bar market tracker/);
  assert.match(
    html,
    /<meta property="og:image" content="https:\/\/www\.pulseticker\.app\/og-v3\.png"\/>/,
  );
  assert.match(
    html,
    /<meta name="twitter:image" content="https:\/\/www\.pulseticker\.app\/og-v3\.png"\/>/,
  );
  assert.doesNotMatch(html, /og-v2\.png/);
  assert.match(html, /Track stocks and markets/);
  assert.match(html, /from your menu bar/);
  assert.doesNotMatch(html, /from your menu bar\./);
  assert.match(html, /data-testid="interactive-preview"/);
  assert.match(html, /Ondas Inc\./);
  assert.match(html, /NVIDIA Corp\./);
  // The English page only shows symbols with English names: no A-share or
  // Hong Kong listings.
  assert.doesNotMatch(html, /工业富联/);
  assert.doesNotMatch(html, /腾讯控股/);
  assert.match(html, /class="market-coverage"/);
  assert.match(html, /Japan and Korea stocks, crypto, precious metals/);
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
  assert.equal(releaseEntries.length, 39);
  assert.ok(html.indexOf("0.14.0") < html.indexOf("0.13.0"));
});

test("serves the Chinese homepage at /zh", async () => {
  const response = await render("/zh");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /<title>Pulse — macOS 菜单栏股票行情工具<\/title>/i);
  assert.match(html, /轻量的 macOS 菜单栏股票行情工具/);
  assert.match(html, /从 Mac 菜单栏看/);
  assert.match(html, /股票与市场行情/);
  assert.doesNotMatch(html, /股票与市场行情。/);
  assert.match(html, /腾讯控股/);
  assert.doesNotMatch(html, /NVIDIA Corp\./);
  assert.match(html, /href="\/zh\/changelog"/);
  assert.match(html, /href="\/"[^>]*>EN<\/a>/);
  assert.match(html, /下载最新版/);
  assert.match(html, /日股、韩股、加密货币、贵金属/);
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

test("serves the Japanese homepage at /ja", async () => {
  const response = await render("/ja");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="ja">/);
  assert.match(html, /<title>Pulse — Mac メニューバー株価アプリ<\/title>/i);
  assert.match(html, /軽量な株価アプリです。/);
  assert.match(html, /Macのメニューバーから、/);
  assert.match(html, /株価とマーケットをすばやく確認/);
  assert.doesNotMatch(html, /株価とマーケットをすばやく確認。/);
  assert.match(html, /日本株・韓国株・暗号資産・貴金属/);
  assert.match(html, /href="\/ja\/changelog"/);
  assert.match(
    html,
    /rel="canonical" href="https:\/\/www\.pulseticker\.app\/ja"/,
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

test("serves the Korean homepage at /ko", async () => {
  const response = await render("/ko");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="ko">/);
  assert.match(html, /<title>Pulse — macOS 메뉴 막대 주식 시세 앱<\/title>/i);
  assert.match(html, /가벼운 시세 앱입니다/);
  assert.match(html, /Mac 메뉴 막대에서/);
  assert.match(html, /주식과 시장을 바로 확인/);
  assert.match(html, /일본·한국 주식, 암호화폐, 귀금속/);
  assert.match(html, /href="\/ko\/changelog"/);
  assert.match(
    html,
    /rel="canonical" href="https:\/\/www\.pulseticker\.app\/ko"/,
  );
});

test("serves the Korean changelog at /ko/changelog", async () => {
  const response = await render("/ko/changelog");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="ko">/);
  assert.match(
    html,
    /<title>Pulse 업데이트 내역 — 모든 릴리스를 한눈에<\/title>/i,
  );
  assert.match(html, /모든 릴리스를,/);
  assert.match(html, /정식 Pulse macOS 앱 아이콘을 넣었습니다/);
  assert.match(html, /href="\/ko"/);
  assert.match(
    html,
    /rel="canonical" href="https:\/\/www\.pulseticker\.app\/ko\/changelog"/,
  );
});

test("marks only the changelog tab active on localized changelog routes", async () => {
  for (const { path, homeHref, changelogHref } of [
    { path: "/zh/changelog", homeHref: "/zh", changelogHref: "/zh/changelog" },
    { path: "/ja/changelog", homeHref: "/ja", changelogHref: "/ja/changelog" },
  ]) {
    const response = await render(path);
    assert.equal(response.status, 200);

    const html = await response.text();
    const navigation = html.match(/<nav class="site-nav"[\s\S]*?<\/nav>/)?.[0];
    assert.ok(navigation, `missing site navigation on ${path}`);

    const homeLink = navigation.match(
      new RegExp(`<a[^>]*href="${homeHref}"[^>]*>`),
    )?.[0];
    const changelogLink = navigation.match(
      new RegExp(`<a[^>]*href="${changelogHref}"[^>]*>`),
    )?.[0];

    assert.ok(homeLink, `missing home link on ${path}`);
    assert.ok(changelogLink, `missing changelog link on ${path}`);
    assert.doesNotMatch(homeLink, /aria-current="page"|data-status="active"/);
    assert.match(changelogLink, /aria-current="page"/);
    assert.equal(navigation.match(/aria-current="page"/g)?.length, 1);
  }
});

test("presents a reconstructed macOS popover and dedicated Omarchy section", async () => {
  for (const path of ["/", "/zh", "/ja", "/ko"]) {
    const response = await render(path);
    assert.equal(response.status, 200);

    const html = await response.text();
    assert.match(html, /data-testid="macos-popover"/);
    assert.match(html, /data-testid="omarchy-section"/);
    assert.match(html, /data-testid="mcp-section"/);
    assert.match(html, /id="omarchy"/);
    assert.match(html, /id="mcp"/);
    assert.match(html, /data-testid="hero-omarchy-cta"/);
    assert.match(html, /data-testid="header-github"/);
    assert.match(html, /github\.com\/fatwang2\/Pulse/);
    assert.match(html, /href="#omarchy"/);
    assert.match(html, /omarchy plugin add/);
    assert.match(html, /omarchy-pulse\.git/);
    assert.match(html, /--enable/);
    assert.match(html, /github\.com\/fatwang2\/omarchy-pulse/);
    assert.match(html, /class="omarchy-preview"/);
    assert.doesNotMatch(html, /\/omarchy\/preview\.png/);
  }

  const english = await (await render("/")).text();
  assert.match(english, /Pulse, now on Omarchy Quattro</);
  assert.match(english, /Explore Omarchy Quattro/);
  assert.match(english, /Local MCP for your agents/);
  assert.match(english, /MCP for agents/);
  assert.match(english, /Settings → Agents → MCP/);
  assert.match(english, /Claude, ChatGPT/);
  assert.match(english, /list_watchlists/);
  assert.match(english, /data-testid="mcp-terminal"/);
  assert.doesNotMatch(english, /Cursor/);

  const chinese = await (await render("/zh")).text();
  assert.match(chinese, /Pulse，也来到 Omarchy Quattro</);
  assert.match(chinese, /Omarchy 插件/);
  assert.match(chinese, /本机 MCP，让智能体直接管自选/);
  assert.match(chinese, /MCP 智能体接入/);
  assert.match(chinese, /设置 → 智能体 → MCP/);
  assert.match(chinese, /Claude、ChatGPT/);
  assert.doesNotMatch(chinese, /Cursor/);

  const japanese = await (await render("/ja")).text();
  assert.match(japanese, /Pulse が Omarchy Quattro にも</);
  assert.match(japanese, /ローカル MCP でエージェントにウォッチリストを/);

  const korean = await (await render("/ko")).text();
  assert.match(korean, /이제 Omarchy Quattro에서도 Pulse를</);
  assert.match(korean, /로컬 MCP로 에이전트가 관심목록을/);
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

  assert.match(homePage, /Track stocks and markets/);
  assert.match(homePage, /macOS menu bar market tracker/);
  assert.match(homePage, /Download for macOS/);
  assert.match(homePage, /Explore Omarchy Quattro/);
  assert.doesNotMatch(homePage, /viewRelease/);
  // Language is a URL path now, not per-browser state.
  assert.doesNotMatch(homePage, /localStorage/);
  assert.match(i18n, /languageCookieName = "pulse-lang"/);
  assert.match(i18n, /preferredLanguage/);
  assert.match(i18n, /detectLanguageFromAcceptLanguage/);
});

test("installs Umami analytics and tracks /download clicks", async () => {
  const rootRoute = await readFile(
    new URL("../src/routes/__root.tsx", import.meta.url),
    "utf8",
  );
  const analyticsEvents = await readFile(
    new URL("../src/components/analytics-events.tsx", import.meta.url),
    "utf8",
  );

  assert.match(rootRoute, /umami\.fatwang2\.com\/script\.js/);
  assert.match(rootRoute, /umamiWebsiteId = "bf5c4531-e265-4858-afd9-ed014426038d"/);
  assert.match(rootRoute, /"data-website-id": umamiWebsiteId/);
  assert.doesNotMatch(rootRoute, /googletagmanager/);
  assert.doesNotMatch(rootRoute, /G-J9GLF06LPP/);
  assert.match(analyticsEvents, /"file_download"/);
  assert.match(analyticsEvents, /url\.pathname !== "\/download"/);
  assert.match(analyticsEvents, /umami\?\.track/);
  assert.doesNotMatch(analyticsEvents, /gtag/);
  assert.doesNotMatch(analyticsEvents, /transport_type/);

  const response = await render();
  const html = await response.text();
  const head = html.slice(0, html.indexOf("</head>"));
  assert.match(head, /umami\.fatwang2\.com\/script\.js/);
  assert.match(head, /data-website-id="bf5c4531-e265-4858-afd9-ed014426038d"/);
  assert.doesNotMatch(head, /googletagmanager/);
});

test("changelog copy ships in every language", async () => {
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
  assert.match(changelogPage, /모든 릴리스를,/);
  assert.match(releaseData, /ko: \[/);
  assert.match(releaseData, /정식 Pulse macOS 앱 아이콘을 넣었습니다。?/);
});

/** Every release must carry every locale, or the timeline renders a hole. */
test("every release has highlights in all four languages", async () => {
  const { releases } = await import(
    new URL("../src/data/releases.ts", import.meta.url).href
  ).catch(() => ({ releases: null }));
  if (!releases) return; // TS source is not importable here; covered by tsc.
  for (const release of releases) {
    for (const language of ["zh", "en", "ja", "ko"]) {
      assert.ok(
        release.highlights[language]?.length > 0,
        `${release.version} is missing ${language} highlights`,
      );
    }
  }
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

test("serves a valid sitemap.xml with all twenty public URLs", async () => {
  const response = await render("/sitemap.xml");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /application\/xml/);

  const xml = await response.text();
  assert.match(xml, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9"/);
  assert.match(xml, /xmlns:xhtml="http:\/\/www\.w3\.org\/1999\/xhtml"/);
  const urls = xml.match(/<loc>https:\/\/www\.pulseticker\.app[^<]*<\/loc>/g) ?? [];
  assert.deepEqual(urls, [
    "<loc>https://www.pulseticker.app/</loc>",
    "<loc>https://www.pulseticker.app/changelog</loc>",
    "<loc>https://www.pulseticker.app/about</loc>",
    "<loc>https://www.pulseticker.app/contact</loc>",
    "<loc>https://www.pulseticker.app/privacy</loc>",
    "<loc>https://www.pulseticker.app/zh</loc>",
    "<loc>https://www.pulseticker.app/zh/changelog</loc>",
    "<loc>https://www.pulseticker.app/zh/about</loc>",
    "<loc>https://www.pulseticker.app/zh/contact</loc>",
    "<loc>https://www.pulseticker.app/zh/privacy</loc>",
    "<loc>https://www.pulseticker.app/ja</loc>",
    "<loc>https://www.pulseticker.app/ja/changelog</loc>",
    "<loc>https://www.pulseticker.app/ja/about</loc>",
    "<loc>https://www.pulseticker.app/ja/contact</loc>",
    "<loc>https://www.pulseticker.app/ja/privacy</loc>",
    "<loc>https://www.pulseticker.app/ko</loc>",
    "<loc>https://www.pulseticker.app/ko/changelog</loc>",
    "<loc>https://www.pulseticker.app/ko/about</loc>",
    "<loc>https://www.pulseticker.app/ko/contact</loc>",
    "<loc>https://www.pulseticker.app/ko/privacy</loc>",
  ]);
  // Each URL entry must carry hreflang alternates for all four locales
  // plus x-default, so Google can consolidate the locale variants.
  assert.match(xml, /hreflang="en" href="https:\/\/www\.pulseticker\.app\/"/);
  assert.match(xml, /hreflang="zh" href="https:\/\/www\.pulseticker\.app\/zh"/);
  assert.match(xml, /hreflang="ja" href="https:\/\/www\.pulseticker\.app\/ja"/);
  assert.match(xml, /hreflang="ko" href="https:\/\/www\.pulseticker\.app\/ko"/);
  assert.match(xml, /hreflang="x-default"/);
});

test("serves a self-hosted robots.txt pointing at the sitemap", async () => {
  const response = await render("/robots.txt");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /text\/plain/);

  const robots = await response.text();
  assert.match(robots, /User-agent: \*/);
  assert.match(robots, /Sitemap: https:\/\/www\.pulseticker\.app\/sitemap\.xml/);
  assert.match(robots, /Sitemap: https:\/\/www\.pulseticker\.app\/sitemap-ko\.xml/);
  // Naver's crawler must be explicitly allowed.
  assert.match(robots, /User-agent: Yeti\nAllow: \//);
  // AI crawlers must be allowed (indexing/reference), not disallowed.
  for (const crawler of ["GPTBot", "ClaudeBot", "PerplexityBot", "Google-Extended"]) {
    assert.match(robots, new RegExp(`User-agent: ${crawler}\\nAllow: /`));
  }
  assert.doesNotMatch(robots, /Disallow: \//);
});

test("serves an Atom feed at /feed.xml with recent releases", async () => {
  const response = await render("/feed.xml");
  assert.equal(response.status, 200);
  assert.match(
    response.headers.get("content-type") ?? "",
    /application\/atom\+xml/,
  );

  const xml = await response.text();
  assert.match(xml, /<feed xmlns="http:\/\/www\.w3\.org\/2005\/Atom">/);
  assert.match(xml, /<title>Pulse Changelog<\/title>/);
  assert.match(
    xml,
    /<link rel="self" href="https:\/\/www\.pulseticker\.app\/feed\.xml"\/>/,
  );
  // Each release should produce an entry.
  const entries = xml.match(/<entry>/g) ?? [];
  assert.ok(entries.length > 0, "feed should contain at least one entry");
  assert.match(xml, /<title>Pulse 0\.14\.0<\/title>/);
});

test("serves a Korean-only sitemap at /sitemap-ko.xml", async () => {
  const response = await render("/sitemap-ko.xml");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /application\/xml/);

  const xml = await response.text();
  assert.match(xml, /<urlset xmlns="http:\/\/www\.sitemaps\.org\/schemas\/sitemap\/0\.9">/);
  const urls = xml.match(/<loc>[^<]*<\/loc>/g) ?? [];
  assert.deepEqual(urls, [
    "<loc>https://www.pulseticker.app/ko</loc>",
    "<loc>https://www.pulseticker.app/ko/changelog</loc>",
    "<loc>https://www.pulseticker.app/ko/about</loc>",
    "<loc>https://www.pulseticker.app/ko/contact</loc>",
    "<loc>https://www.pulseticker.app/ko/privacy</loc>",
  ]);
});

test("Korean pages carry the meta content-language tag for Naver", async () => {
  const response = await render("/ko");
  const html = await response.text();
  assert.match(
    html,
    /<meta http-equiv="content-language" content="ko"\/>/,
  );
});

test("non-Korean pages do not carry the content-language meta tag", async () => {
  for (const path of ["/", "/zh", "/ja"]) {
    const response = await render(path);
    const html = await response.text();
    assert.doesNotMatch(html, /http-equiv="content-language"/);
  }
});

test("HTML head links to the Atom feed", async () => {
  const response = await render();
  const html = await response.text();
  assert.match(
    html,
    /rel="alternate" type="application\/atom\+xml" href="\/feed\.xml"/,
  );
});

test("embeds SoftwareApplication JSON-LD on the homepage", async () => {
  const response = await render();
  const html = await response.text();

  assert.match(html, /<script type="application\/ld\+json">/);
  assert.match(html, /"@type":"SoftwareApplication"/);
  assert.match(html, /"operatingSystem":"macOS"/);
  assert.match(html, /"downloadUrl":"https:\/\/www\.pulseticker\.app\/download"/);
  assert.match(html, /"sameAs":\["https:\/\/github\.com\/fatwang2\/Pulse","https:\/\/github\.com\/superagents-lab"\]/);
  assert.match(html, /"inLanguage":\["en","zh","ja","ko"\]/);
});

test("embeds Organization JSON-LD with contactPoint and address", async () => {
  const response = await render();
  const html = await response.text();

  assert.match(html, /"@type":"Organization"/);
  assert.match(html, /"name":"SuperAgents, LLC"/);
  assert.match(html, /"alternateName":"Pulse"/);
  assert.match(html, /"@type":"ContactPoint"/);
  assert.match(html, /"email":"hello@pulseticker\.app"/);
  assert.match(html, /"contactType":"customer support"/);
  assert.match(html, /"@type":"PostalAddress"/);
  assert.match(html, /"streetAddress":"131 Continental Dr, Suite 305"/);
  assert.match(html, /"addressLocality":"Newark"/);
  assert.match(html, /"addressRegion":"DE"/);
  assert.match(html, /"postalCode":"19713"/);
  assert.match(html, /"addressCountry":"US"/);
});

test("SoftwareApplication lists PulseTicker as an alternateName", async () => {
  const response = await render();
  const html = await response.text();
  assert.match(html, /"alternateName":\["PulseTicker"/);
});

test("server-renders the about page at /about", async () => {
  const response = await render("/about");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>About Pulse/);
  assert.match(html, /Pulse solves one problem/);
  assert.match(html, /Why we built Pulse/);
  assert.match(html, /SuperAgents, LLC/);
  assert.match(html, /131 Continental Dr/);
  assert.match(html, /class="info-page"/);
  assert.match(html, /rel="canonical" href="https:\/\/www\.pulseticker\.app\/about"/);
  // At least 500 characters of meaningful content.
  assert.ok(html.length > 2500, "about page should have substantial content");
});

test("server-renders the contact page at /contact", async () => {
  const response = await render("/contact");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>Contact Pulse/);
  assert.match(html, /Get in touch/);
  assert.match(html, /hello@pulseticker\.app/);
  assert.match(html, /sys@pulseticker\.app/);
  assert.match(html, /github\.com\/fatwang2\/Pulse\/issues/);
  assert.match(html, /rel="canonical" href="https:\/\/www\.pulseticker\.app\/contact"/);
});

test("server-renders the privacy page at /privacy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>Privacy/);
  assert.match(html, /Anonymous usage analytics/);
  assert.match(html, /TelemetryDeck/);
  assert.match(html, /SuperAgents, LLC/);
  assert.match(html, /131 Continental Dr/);
  assert.match(html, /rel="canonical" href="https:\/\/www\.pulseticker\.app\/privacy"/);
});

test("serves localized about page at /zh/about", async () => {
  const response = await render("/zh/about");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /<title>关于 Pulse/);
  assert.match(html, /Pulse 只解决一个问题/);
  assert.match(html, /rel="canonical" href="https:\/\/www\.pulseticker\.app\/zh\/about"/);
});

test("redirects /en/about to /about", async () => {
  const response = await render("/en/about");
  assert.equal(response.status, 302);
  assert.equal(response.headers.get("location"), "/about");
});

test("serves llms.txt with when-to-use guidance", async () => {
  const response = await render("/llms.txt");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /text\/markdown/);

  const text = await response.text();
  assert.match(text, /^# Pulse$/m);
  assert.match(text, /## When to use this/);
  assert.match(text, /NOT a trading terminal/);
  assert.match(text, /Free and open source/);
  assert.match(text, /https:\/\/www\.pulseticker\.app\/download/);
  assert.match(text, /https:\/\/github\.com\/fatwang2\/Pulse/);
  assert.match(text, /SuperAgents, LLC/);
});

test("serves markdown via Accept content negotiation", async () => {
  const response = await render("/", { accept: "text/markdown" });
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /text\/markdown/);
  assert.match(response.headers.get("vary") ?? "", /Accept/);

  const text = await response.text();
  assert.match(text, /^# Pulse$/m);
  assert.match(text, /## When to use this/);
});

test("returns a real 404 for unknown HTML paths", async () => {
  const response = await render("/this-page-does-not-exist");
  assert.equal(response.status, 404);
  assert.match(response.headers.get("content-type") ?? "", /text\/markdown/);

  const body = await response.text();
  assert.match(body, /404 — Not Found/);
  assert.match(body, /sitemap\.xml/);
  assert.match(body, /llms\.txt/);
});

test("returns 404 for unknown paths with Accept: text/markdown", async () => {
  const response = await render("/nonexistent-markdown", { accept: "text/markdown" });
  assert.equal(response.status, 404);
  assert.match(response.headers.get("content-type") ?? "", /text\/markdown/);

  const body = await response.text();
  assert.match(body, /404 — Not Found/);
});

test("returns 404 for unknown paths with Accept: */*", async () => {
  const response = await render("/nonexistent-wildcard", { accept: "*/*" });
  assert.equal(response.status, 404);
});

test("HTML responses carry a Vary header for content negotiation", async () => {
  const response = await render("/");
  assert.equal(response.status, 200);
  const vary = response.headers.get("vary") ?? "";
  assert.match(vary, /Accept/);
});
