import { Link } from "@tanstack/react-router";
import { FeatureShowcase } from "./feature-showcase";
import { InteractivePreview } from "./interactive-preview";
import { SiteHeader } from "./site-header";
import { releases } from "../data/releases";
import { changelogPath, type Language } from "../i18n";

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

const translations = {
  zh: {
    overline: "macOS 菜单栏行情工具",
    headlineFirst: "从 Mac 菜单栏快速查看",
    headlineSecond: "股票与市场行情",
    intro:
      "Pulse 把你关心的价格、走势和持仓盈亏放进菜单栏。从盘前到盘后，不打断工作，也能随时知道市场发生了什么。",
    featuresLabel: "主要功能",
    features: ["多分组自选", "持仓盈亏", "蜡烛图与盘前盘后", "菜单栏行情轮播"],
    downloadLabel: "下载最新版",
    githubLabel: "GitHub 开源",
    whatsNew: "{date}发布 · 查看更新日志",
    screenshotAlt:
      "Pulse 自选列表截图，展示美股、A 股、港股与加密货币的价格和走势图",
    markets: "支持美股、港股、A 股、加密货币、指数与 ETF",
    dataSourcesLabel: "行情数据来源",
    dataSourcesNote:
      "仅用于说明数据来源，覆盖范围因市场而异；行情数据仅供参考，不构成投资建议。",
  },
  en: {
    overline: "macOS menu bar market tracker",
    headlineFirst: "Track stocks and markets",
    headlineSecond: "from your menu bar",
    intro:
      "Pulse puts the prices, trends, and position performance you care about in the menu bar—from pre-market to after hours, without leaving what you’re doing.",
    featuresLabel: "Key features",
    features: [
      "Multi-list watchlists",
      "Position P&L",
      "Candles & extended hours",
      "Menu bar ticker",
    ],
    downloadLabel: "Download for macOS",
    githubLabel: "View on GitHub",
    whatsNew: "Released {date} · View changelog",
    screenshotAlt:
      "Pulse watchlist showing prices and sparklines for US stocks and crypto",
    markets: "US, Hong Kong and China stocks, crypto, indices, and ETFs",
    dataSourcesLabel: "Market data sources",
    dataSourcesNote:
      "Shown for source identification only; coverage varies by market. Market data is not investment advice.",
  },
  ja: {
    overline: "macOS メニューバーの株価トラッカー",
    headlineFirst: "Macのメニューバーから、",
    headlineSecond: "株価とマーケットをすばやく確認",
    intro:
      "Pulse は、気になる価格・トレンド・評価損益をメニューバーに。プレマーケットからアフターマーケットまで、作業を中断せずに市場の動きを把握できます。",
    featuresLabel: "主な機能",
    features: [
      "複数のウォッチリスト",
      "評価損益",
      "ローソク足と時間外取引",
      "メニューバーティッカー",
    ],
    downloadLabel: "macOS 版をダウンロード",
    githubLabel: "GitHub で見る",
    whatsNew: "{date}リリース · 更新履歴を見る",
    screenshotAlt:
      "米国株や暗号資産の価格とスパークラインを表示する Pulse のウォッチリスト",
    markets: "米国株・香港株・中国A株・暗号資産・指数・ETF に対応",
    dataSourcesLabel: "マーケットデータの提供元",
    dataSourcesNote:
      "データ提供元の表示のみを目的としています。対応範囲は市場により異なります。マーケットデータは投資助言ではありません。",
  },
} as const;

const dateLocales: Record<Language, string> = {
  zh: "zh-CN",
  en: "en-US",
  ja: "ja-JP",
};

function formatReleaseDate(date: string, language: Language) {
  const [year, month, day] = date.split("-").map(Number);
  return new Intl.DateTimeFormat(dateLocales[language], {
    year: "numeric",
    month: language === "en" ? "short" : "long",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

export function HomePage({ language }: { language: Language }) {
  const copy = translations[language];
  const latestRelease = releases[0];
  const whatsNewLabel = copy.whatsNew.replace(
    "{date}",
    formatReleaseDate(latestRelease.date, language),
  );

  return (
    <main className="landing">
      <div className="market-pulse" aria-hidden="true">
        <svg viewBox="134 215 756 580" preserveAspectRatio="xMidYMid meet">
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
            d="M170 512 L292 512 C316 512 328 476 348 476 C371 476 383 537 405 537 C425 537 444 423 493 278 C502 251 520 251 529 280 L627 728 C634 759 654 759 666 730 L738 520 C744 503 756 498 774 498 L854 498"
          />
        </svg>
      </div>

      <SiteHeader language={language} page="home" />

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
            {copy.features.map((feature, index) => (
              <span key={feature} className="feature-line-item">
                {index > 0 ? <i /> : null}
                <span>{feature}</span>
              </span>
            ))}
          </div>

          <div className="actions">
            <a className="cta-button cta-primary" href={latestReleaseUrl}>
              <img src="/apple.svg" alt="" width={15} height={15} aria-hidden="true" />
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

          <Link
            className="whats-new"
            to={changelogPath(language)}
            data-testid="whats-new"
          >
            <span className="whats-new-badge">{`v${latestRelease.version}`}</span>
            {whatsNewLabel}
            <span aria-hidden="true">→</span>
          </Link>
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

      <FeatureShowcase language={language} />

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
              <img
                src={source.src}
                alt={source.name}
                width={source.width}
                height={source.height}
              />
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}
