import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
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
  assert.match(html, /工业富联/);
  assert.match(html, /class="market-pulse" aria-hidden="true"/);
  assert.match(html, /class="brand-mark"/);
  assert.match(html, /href="\/download"/);
  assert.doesNotMatch(html, /github\.com\/fatwang2\/Pulse\/releases\/latest/);
  assert.match(html, /apple\.svg/);
  assert.match(html, /Market data sources/);
  assert.match(html, /providers\/longbridge\.png/);
  assert.match(html, /providers\/binance\.svg/);
  assert.match(html, /providers\/tencent\.png/);
  assert.match(html, /providers\/yahoo-finance\.svg/);
  assert.match(html, /aria-pressed="false"[^>]*>中文<\/button>/);
  assert.match(html, /aria-pressed="true"[^>]*>EN<\/button>/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/);
});

test("includes English copy and remembered language selection", async () => {
  const page = await readFile(
    new URL("../app/page.tsx", import.meta.url),
    "utf8",
  );

  assert.match(page, /Your market,/);
  assert.match(page, /macOS menu bar market tracker/);
  assert.match(page, /Download for macOS/);
  assert.match(page, /View on GitHub/);
  assert.match(page, /navigator\.language/);
  assert.match(page, /localStorage\.getItem\("pulse-language"\)/);
  assert.match(page, /localStorage\.setItem\("pulse-language", nextLanguage\)/);
  assert.match(page, /document\.documentElement\.lang/);
});

test("redirects the stable download URL to the versioned DMG", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("download-test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  const response = await worker.fetch(
    new Request("http://localhost/download", { redirect: "manual" }),
    {},
    {},
  );

  assert.equal(response.status, 302);
  assert.equal(
    response.headers.get("location"),
    "http://localhost/downloads/v0.4.1/Pulse-0.4.1.dmg",
  );
});

test("serves a stored DMG from the Sites R2 binding", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("r2-test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const body = new TextEncoder().encode("dmg");

  const response = await worker.fetch(
    new Request("http://localhost/downloads/v0.4.1/Pulse-0.4.1.dmg"),
    {
      DOWNLOADS: {
        async get(key) {
          assert.equal(key, "releases/v0.4.1/Pulse-0.4.1.dmg");
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
    'attachment; filename="Pulse-0.4.1.dmg"',
  );
  assert.equal(
    response.headers.get("content-type"),
    "application/x-apple-diskimage",
  );
  assert.equal(response.headers.get("x-pulse-version"), "0.4.1");
  assert.equal(new TextDecoder().decode(await response.arrayBuffer()), "dmg");
});
