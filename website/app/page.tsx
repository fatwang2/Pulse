"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { InteractivePreview } from "./interactive-preview";

const latestReleaseUrl = "/download";
const repositoryUrl = "https://github.com/fatwang2/Pulse";

const dataSources = [
  {
    id: "longbridge",
    name: "Longbridge",
    src: "/providers/longbridge.png",
    width: 633,
    height: 139,
  },
  {
    id: "binance",
    name: "Binance",
    src: "/providers/binance.svg",
    width: 632,
    height: 127,
  },
  {
    id: "tencent",
    name: "Tencent",
    src: "/providers/tencent.png?v=1",
    width: 800,
    height: 241,
  },
  {
    id: "yahoo-finance",
    name: "Yahoo Finance",
    src: "/providers/yahoo-finance.svg",
    width: 1284,
    height: 181,
  },
] as const;

type Language = "zh" | "en";

const translations = {
  zh: {
    homeLabel: "Pulse 首页",
    changelogLabel: "更新日志",
    languageLabel: "切换网站语言",
    overline: "macOS 菜单栏行情工具",
    headlineFirst: "你的市场，",
    headlineSecond: "一眼掌握。",
    intro:
      "Pulse 把你关心的价格、走势和持仓盈亏放进菜单栏。不打断工作，也能随时知道市场发生了什么。",
    featuresLabel: "主要功能",
    features: ["自选列表", "持仓盈亏", "分时与 K 线"],
    downloadLabel: "下载最新版",
    githubLabel: "GitHub 开源",
    screenshotAlt:
      "Pulse 自选列表截图，展示美股、A 股、港股与加密货币的价格和走势图",
    markets: "支持美股、港股、A 股、加密货币、指数与 ETF",
    dataSourcesLabel: "行情数据来源",
    dataSourcesNote:
      "仅用于说明数据来源，覆盖范围因市场而异；行情数据仅供参考，不构成投资建议。",
    pageTitle: "Pulse — 你的市场，一眼掌握",
  },
  en: {
    homeLabel: "Pulse home",
    changelogLabel: "Changelog",
    languageLabel: "Change website language",
    overline: "macOS menu bar market tracker",
    headlineFirst: "Your market,",
    headlineSecond: "at a glance.",
    intro:
      "Pulse puts the prices, trends, and position performance you care about in the menu bar—so you can stay informed without leaving what you’re doing.",
    featuresLabel: "Key features",
    features: ["Watchlist", "Position P&L", "Intraday & candles"],
    downloadLabel: "Download for macOS",
    githubLabel: "View on GitHub",
    screenshotAlt:
      "Pulse watchlist showing prices and sparklines for US, China, Hong Kong, and crypto markets",
    markets: "US, Hong Kong and China stocks, crypto, indices, and ETFs",
    dataSourcesLabel: "Market data sources",
    dataSourcesNote:
      "Shown for source identification only; coverage varies by market. Market data is not investment advice.",
    pageTitle: "Pulse — Your market, at a glance",
  },
} as const;

export default function Home() {
  const [language, setLanguage] = useState<Language>("en");
  const copy = translations[language];

  useEffect(() => {
    const savedLanguage = window.localStorage.getItem("pulse-language");
    const preferredLanguage =
      savedLanguage === "zh" || savedLanguage === "en"
        ? savedLanguage
        : window.navigator.language.toLowerCase().startsWith("zh")
          ? "zh"
          : "en";

    const frame = window.requestAnimationFrame(() => {
      setLanguage(preferredLanguage);
    });

    return () => window.cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
    document.title = copy.pageTitle;
  }, [copy.pageTitle, language]);

  function selectLanguage(nextLanguage: Language) {
    setLanguage(nextLanguage);
    window.localStorage.setItem("pulse-language", nextLanguage);
  }

  return (
    <main className="landing">
      <div className="market-pulse" aria-hidden="true">
        <svg viewBox="0 0 1440 640" preserveAspectRatio="none">
          <defs>
            <linearGradient id="pulse-stroke" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#0a84ff" stopOpacity="0" />
              <stop offset="0.34" stopColor="#0a84ff" stopOpacity="0.42" />
              <stop offset="0.7" stopColor="#20c4df" stopOpacity="0.26" />
              <stop offset="1" stopColor="#20c4df" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            pathLength="1"
            d="M0 394 C150 394 218 388 318 390 C398 391 434 390 482 389 L531 389 L557 365 L580 416 L614 309 L652 468 L688 350 L719 391 C806 393 903 391 990 391 C1112 391 1268 392 1440 389"
          />
        </svg>
      </div>

      <header className="header shell">
        <Link className="brand" href="/" aria-label={copy.homeLabel}>
          <span className="brand-mark">
            <Image
              src="/pulse-icon.png"
              alt=""
              width={34}
              height={34}
              priority
              unoptimized
            />
          </span>
          <span>Pulse</span>
        </Link>
        <div className="header-actions">
          <nav className="site-nav" aria-label={copy.homeLabel}>
            <Link href="/changelog">{copy.changelogLabel}</Link>
          </nav>
          <div className="language-switcher" aria-label={copy.languageLabel}>
            <button
              type="button"
              aria-pressed={language === "zh"}
              className={language === "zh" ? "active" : undefined}
              onClick={() => selectLanguage("zh")}
            >
              中文
            </button>
            <button
              type="button"
              aria-pressed={language === "en"}
              className={language === "en" ? "active" : undefined}
              onClick={() => selectLanguage("en")}
            >
              EN
            </button>
          </div>
        </div>
      </header>

      <section className="hero shell" id="top">
        <div className="copy">
          <p className="overline">{copy.overline}</p>
          <h1>
            {copy.headlineFirst}
            <br />
            {copy.headlineSecond}
          </h1>
          <p className="intro">{copy.intro}</p>

          <div className="feature-line" aria-label={copy.featuresLabel}>
            <span>{copy.features[0]}</span>
            <i />
            <span>{copy.features[1]}</span>
            <i />
            <span>{copy.features[2]}</span>
          </div>

          <div className="actions">
            <a className="cta-button cta-primary" href={latestReleaseUrl}>
              <Image src="/apple.svg" alt="" width={15} height={15} aria-hidden="true" />
              {copy.downloadLabel}
            </a>
            <a
              className="cta-button cta-secondary"
              href={repositoryUrl}
              target="_blank"
              rel="noreferrer"
            >
              {copy.githubLabel}
            </a>
          </div>
        </div>

        <div className="product-shot">
          <div className="screenshot-card">
            <div className="screenshot-topbar">
              <span>
                <i />
                <i />
                <i />
              </span>
            </div>
            <div className="screenshot-viewport">
              <InteractivePreview language={language} ariaLabel={copy.screenshotAlt} />
            </div>
          </div>
        </div>
      </section>

      <section
        className="data-sources shell"
        aria-labelledby="data-sources-title"
      >
        <div className="data-sources-heading">
          <h2 id="data-sources-title">{copy.dataSourcesLabel}</h2>
          <p>{copy.dataSourcesNote}</p>
        </div>
        <ul className="provider-logos">
          {dataSources.map((source) => (
            <li
              className={`provider-logo provider-logo--${source.id}`}
              key={source.id}
            >
              <Image
                src={source.src}
                alt={source.name}
                width={source.width}
                height={source.height}
                unoptimized
              />
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
