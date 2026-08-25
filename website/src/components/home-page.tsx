import { useEffect, useRef, useState } from "react";
import { Link } from "@tanstack/react-router";
import { FeatureShowcase } from "./feature-showcase";
import { InteractivePreview } from "./interactive-preview";
import { OmarchyPreview } from "./omarchy-preview";
import { SiteHeader } from "./site-header";
import { releases } from "../data/releases";
import { changelogPath, type Language } from "../i18n";

const latestReleaseUrl = "/download";
const omarchyUrl = "https://github.com/fatwang2/omarchy-pulse";
const omarchyInstallCommand =
  "omarchy plugin add https://github.com/fatwang2/omarchy-pulse.git --enable";

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
  {
    id: "naver",
    name: "Naver",
    src: "/providers/naver.svg",
    width: 22,
    height: 22,
  },
  {
    id: "sge",
    name: "Shanghai Gold Exchange",
    src: "/providers/sge.png",
    width: 198,
    height: 46,
  },
  {
    id: "eastmoney",
    name: "Eastmoney",
    src: "/providers/eastmoney.png",
    width: 104,
    height: 26,
  },
  {
    id: "sina",
    name: "Sina Finance",
    src: "/providers/sina.png",
    width: 128,
    height: 128,
  },
] as const;

const translations = {
  zh: {
    overline: "macOS 菜单栏行情工具",
    headlineFirst: "从 Mac 菜单栏看",
    headlineSecond: "股票与市场行情",
    intro:
      "Pulse 把你关心的价格、走势和持仓盈亏放进菜单栏。从盘前到盘后，不打断工作，也能随时知道市场发生了什么。",
    featuresLabel: "主要功能",
    features: ["多分组自选", "持仓盈亏", "蜡烛图与盘前盘后", "MCP 智能体接入"],
    downloadLabel: "下载最新版",
    omarchyLabel: "Omarchy 插件",
    whatsNew: "{date}发布 · 查看更新日志",
    screenshotAlt:
      "Pulse 菜单栏浮层演示，展示美股、A 股、港股与加密货币的价格和走势图",
    markets: "支持美股、港股、A 股、日股、韩股、加密货币、贵金属、指数与 ETF",
    mcp: {
      title: "本机 MCP，让智能体直接管自选",
      description:
        "在设置中开启后，Pulse 在本机提供 Streamable HTTP 的 MCP 服务。Claude、ChatGPT 以及任何支持 MCP 的客户端，都可以读取并编辑你的自选分组、持仓与交易记录——仅绑定 127.0.0.1，用钥匙串中的 Bearer 令牌鉴权。",
      path: "设置 → 智能体 → MCP",
      terminal: {
        label: "pulse · mcp",
        ariaLabel: "MCP 工具调用示意：列出分组、添加标的、记录交易、调整顺序",
        lines: [
          { role: "call", text: "list_watchlists" },
          { role: "result", text: "Tech · 港股 · 自选  ·  18 symbols" },
          { role: "call", text: "add_symbol  us:NVDA → Tech" },
          { role: "result", text: "ok" },
          { role: "call", text: "record_trade  buy 10 NVDA @ 120" },
          { role: "result", text: "qty 10 · avg 120.00" },
          { role: "call", text: "reorder_groups" },
          { role: "result", text: "Tech · 港股 · 自选" },
        ],
      },
    },
    platforms: {
      omarchy: {
        title: "Pulse，也来到 Omarchy Quattro",
        description:
          "为 Omarchy Quattro 原生打造的 Quickshell 行情面板。无需离开桌面，就能查看命名分组、搜索标的，并打开分时走势与蜡烛图。",
        installLabel: "安装 Omarchy Quattro 插件",
        copy: "复制命令",
        copying: "正在复制",
        copied: "已复制",
        copyError: "无法复制，请手动选择命令。",
        link: "在 GitHub 查看源码",
        imageCaption: "Pulse for Omarchy Quattro · Quickshell",
        imageAlt: "Omarchy Quattro 状态栏中的 Pulse 面板，展示带走势线的自选列表",
      },
    },
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
      "MCP for agents",
    ],
    downloadLabel: "Download for macOS",
    omarchyLabel: "Explore Omarchy Quattro",
    whatsNew: "Released {date} · View changelog",
    screenshotAlt:
      "Pulse menu bar popover showing prices and sparklines for US stocks and crypto",
    markets: "US, Hong Kong, China, Japan and Korea stocks, crypto, precious metals, indices, and ETFs",
    mcp: {
      title: "Local MCP for your agents",
      description:
        "Turn it on in Settings and Pulse serves Streamable HTTP MCP on your Mac. Claude, ChatGPT, and any MCP-compatible client can read and edit your watchlists, positions, and trades — bound to 127.0.0.1 only, gated by a Keychain Bearer token.",
      path: "Settings → Agents → MCP",
      terminal: {
        label: "pulse · mcp",
        ariaLabel:
          "Sample MCP tool session: list groups, add a symbol, record a trade, reorder groups",
        lines: [
          { role: "call", text: "list_watchlists" },
          { role: "result", text: "Tech · HK · Watchlist  ·  18 symbols" },
          { role: "call", text: "add_symbol  us:NVDA → Tech" },
          { role: "result", text: "ok" },
          { role: "call", text: "record_trade  buy 10 NVDA @ 120" },
          { role: "result", text: "qty 10 · avg 120.00" },
          { role: "call", text: "reorder_groups" },
          { role: "result", text: "Tech · HK · Watchlist" },
        ],
      },
    },
    platforms: {
      omarchy: {
        title: "Pulse, now on Omarchy Quattro",
        description:
          "A native Quickshell market panel for Omarchy Quattro. Check named watchlists, search symbols, and open session lines or candlesticks without leaving your desktop.",
        installLabel: "Install the Omarchy Quattro plugin",
        copy: "Copy command",
        copying: "Copying",
        copied: "Copied",
        copyError: "Couldn’t copy. Select the command and copy it manually.",
        link: "View source on GitHub",
        imageCaption: "Pulse for Omarchy Quattro · Quickshell",
        imageAlt:
          "Pulse panel in the Omarchy Quattro bar showing a watchlist with sparklines",
      },
    },
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
      "エージェント向け MCP",
    ],
    downloadLabel: "macOS 版をダウンロード",
    omarchyLabel: "Omarchy Quattro 版を見る",
    whatsNew: "{date}リリース · 更新履歴を見る",
    screenshotAlt:
      "米国株や暗号資産の価格とスパークラインを表示する Pulse のメニューバーポップオーバー",
    markets: "米国株・香港株・中国A株・日本株・韓国株・暗号資産・貴金属・指数・ETF に対応",
    mcp: {
      title: "ローカル MCP でエージェントにウォッチリストを",
      description:
        "設定で有効にすると、Pulse が Mac 上で Streamable HTTP の MCP を提供します。Claude、ChatGPT、その他 MCP 対応クライアントがウォッチリスト、保有、取引を読み書きできます——127.0.0.1 のみにバインドし、Keychain の Bearer トークンで保護します。",
      path: "設定 → エージェント → MCP",
      terminal: {
        label: "pulse · mcp",
        ariaLabel:
          "MCP ツール呼び出しの例：グループ一覧、銘柄追加、取引記録、並び替え",
        lines: [
          { role: "call", text: "list_watchlists" },
          { role: "result", text: "Tech · 港股 · 自選  ·  18 symbols" },
          { role: "call", text: "add_symbol  us:NVDA → Tech" },
          { role: "result", text: "ok" },
          { role: "call", text: "record_trade  buy 10 NVDA @ 120" },
          { role: "result", text: "qty 10 · avg 120.00" },
          { role: "call", text: "reorder_groups" },
          { role: "result", text: "Tech · 港股 · 自選" },
        ],
      },
    },
    platforms: {
      omarchy: {
        title: "Pulse が Omarchy Quattro にも",
        description:
          "Omarchy Quattro 向けにネイティブで作られた Quickshell マーケットパネル。デスクトップを離れずに、名前付きリスト、銘柄検索、分足ライン、ローソク足を利用できます。",
        installLabel: "Omarchy Quattro プラグインをインストール",
        copy: "コマンドをコピー",
        copying: "コピー中",
        copied: "コピーしました",
        copyError: "コピーできませんでした。コマンドを選択して手動でコピーしてください。",
        link: "GitHub でソースを見る",
        imageCaption: "Pulse for Omarchy Quattro · Quickshell",
        imageAlt:
          "Omarchy Quattro のバーに表示された Pulse パネル。スパークライン付きのウォッチリスト",
      },
    },
    dataSourcesLabel: "マーケットデータの提供元",
    dataSourcesNote:
      "データ提供元の表示のみを目的としています。対応範囲は市場により異なります。マーケットデータは投資助言ではありません。",
  },
  ko: {
    overline: "macOS 메뉴 막대 시세 앱",
    headlineFirst: "Mac 메뉴 막대에서",
    headlineSecond: "주식과 시장을 바로 확인",
    intro:
      "Pulse는 신경 쓰는 종목의 가격과 흐름, 보유 손익을 메뉴 막대에 올려 둡니다. 장전부터 장후까지, 하던 일을 멈추지 않고도 시장이 어떻게 움직이는지 알 수 있습니다.",
    featuresLabel: "주요 기능",
    features: [
      "여러 개의 관심목록",
      "보유 손익",
      "캔들차트와 시간외 거래",
      "에이전트용 MCP",
    ],
    downloadLabel: "macOS용 다운로드",
    omarchyLabel: "Omarchy Quattro 버전 보기",
    whatsNew: "{date} 릴리스 · 업데이트 내역 보기",
    screenshotAlt:
      "미국 주식과 암호화폐의 가격과 추세선을 보여 주는 Pulse 메뉴 막대 팝오버",
    markets: "미국·홍콩·중국 A주·일본·한국 주식, 암호화폐, 귀금속, 지수, ETF 지원",
    mcp: {
      title: "로컬 MCP로 에이전트가 관심목록을",
      description:
        "설정에서 켜면 Pulse가 Mac에서 Streamable HTTP MCP를 제공합니다. Claude, ChatGPT 및 MCP를 지원하는 모든 클라이언트가 관심목록, 보유, 거래를 읽고 수정할 수 있습니다 — 127.0.0.1에만 바인딩되며 Keychain Bearer 토큰으로 보호됩니다.",
      path: "설정 → 에이전트 → MCP",
      terminal: {
        label: "pulse · mcp",
        ariaLabel:
          "MCP 도구 호출 예시: 그룹 목록, 종목 추가, 거래 기록, 순서 변경",
        lines: [
          { role: "call", text: "list_watchlists" },
          { role: "result", text: "Tech · 港股 · 관심  ·  18 symbols" },
          { role: "call", text: "add_symbol  us:NVDA → Tech" },
          { role: "result", text: "ok" },
          { role: "call", text: "record_trade  buy 10 NVDA @ 120" },
          { role: "result", text: "qty 10 · avg 120.00" },
          { role: "call", text: "reorder_groups" },
          { role: "result", text: "Tech · 港股 · 관심" },
        ],
      },
    },
    platforms: {
      omarchy: {
        title: "이제 Omarchy Quattro에서도 Pulse를",
        description:
          "Omarchy Quattro를 위해 네이티브로 만든 Quickshell 시세 패널입니다. 데스크톱을 벗어나지 않고 이름 붙인 관심목록, 종목 검색, 장중 라인과 캔들차트를 확인할 수 있습니다.",
        installLabel: "Omarchy Quattro 플러그인 설치",
        copy: "명령어 복사",
        copying: "복사 중",
        copied: "복사됨",
        copyError: "복사하지 못했습니다. 명령어를 선택해 직접 복사해 주세요.",
        link: "GitHub에서 소스 보기",
        imageCaption: "Pulse for Omarchy Quattro · Quickshell",
        imageAlt:
          "Omarchy Quattro 막대에 표시된 Pulse 패널. 추세선이 있는 관심목록",
      },
    },
    dataSourcesLabel: "시세 데이터 제공처",
    dataSourcesNote:
      "데이터 출처를 밝히기 위한 표시이며, 지원 범위는 시장마다 다릅니다. 시세 데이터는 투자 자문이 아닙니다.",
  },
} as const;

const dateLocales: Record<Language, string> = {
  zh: "zh-CN",
  en: "en-US",
  ja: "ja-JP",
  ko: "ko-KR",
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

function OmarchyInstall({
  label,
  copyLabel,
  copyingLabel,
  copiedLabel,
  copyErrorLabel,
}: {
  label: string;
  copyLabel: string;
  copyingLabel: string;
  copiedLabel: string;
  copyErrorLabel: string;
}) {
  const [state, setState] = useState<"idle" | "copying" | "copied" | "error">(
    "idle",
  );
  const timeoutRef = useRef<number | undefined>(undefined);

  useEffect(
    () => () => window.clearTimeout(timeoutRef.current),
    [],
  );

  async function copyCommand() {
    setState("copying");
    window.clearTimeout(timeoutRef.current);

    try {
      await navigator.clipboard.writeText(omarchyInstallCommand);
      setState("copied");
      timeoutRef.current = window.setTimeout(() => setState("idle"), 1800);
    } catch {
      setState("error");
    }
  }

  const buttonLabel =
    state === "copying"
      ? copyingLabel
      : state === "copied"
        ? copiedLabel
        : copyLabel;

  return (
    <div className="omarchy-install">
      <span className="omarchy-install-label" id="omarchy-install-label">
        {label}
      </span>
      <div className="omarchy-command" data-state={state}>
        <span className="omarchy-command-prompt" aria-hidden="true">
          $
        </span>
        <code
          aria-labelledby="omarchy-install-label"
          title={omarchyInstallCommand}
          tabIndex={0}
        >
          {omarchyInstallCommand}
        </code>
        <button
          className="omarchy-copy-button"
          type="button"
          onClick={copyCommand}
          aria-label={buttonLabel}
          title={buttonLabel}
          disabled={state === "copying"}
          data-state={state}
          data-testid="omarchy-copy"
        >
          {state === "copied" ? (
            <svg aria-hidden="true" viewBox="0 0 16 16">
              <path d="m3.5 8.5 2.7 2.7 6.3-6.4" />
            </svg>
          ) : (
            <svg aria-hidden="true" viewBox="0 0 16 16">
              <rect x="5.5" y="5.5" width="7" height="7" rx="1.5" />
              <path d="M10.5 5.5v-1A1.5 1.5 0 0 0 9 3H4.5A1.5 1.5 0 0 0 3 4.5V9a1.5 1.5 0 0 0 1.5 1.5h1" />
            </svg>
          )}
        </button>
      </div>
      <p className="omarchy-copy-error" role="status">
        {state === "error" ? copyErrorLabel : ""}
      </p>
    </div>
  );
}

function OmarchySection({ language }: { language: Language }) {
  const text = translations[language].platforms.omarchy;

  return (
    <section
      className="omarchy-section shell"
      id="omarchy"
      aria-labelledby="omarchy-title"
      data-testid="omarchy-section"
    >
      <div className="omarchy-layout">
        <div className="omarchy-copy">
          <h2 id="omarchy-title">{text.title}</h2>
          <p className="platform-description">{text.description}</p>
          <OmarchyInstall
            label={text.installLabel}
            copyLabel={text.copy}
            copyingLabel={text.copying}
            copiedLabel={text.copied}
            copyErrorLabel={text.copyError}
          />
          <a
            className="omarchy-link"
            href={omarchyUrl}
            target="_blank"
            rel="noreferrer"
          >
            {text.link}
            <svg aria-hidden="true" viewBox="0 0 16 16">
              <path d="M5 11 11 5M6 5h5v5" />
            </svg>
          </a>
        </div>

        <figure className="omarchy-shot">
          <div className="omarchy-shot-frame">
            <OmarchyPreview ariaLabel={text.imageAlt} />
          </div>
          <figcaption>{text.imageCaption}</figcaption>
        </figure>
      </div>
    </section>
  );
}

function MCPSection({ language }: { language: Language }) {
  const text = translations[language].mcp;

  return (
    <section
      className="mcp-section shell"
      id="mcp"
      aria-labelledby="mcp-title"
      data-testid="mcp-section"
    >
      <div className="mcp-layout">
        <div className="mcp-copy">
          <h2 id="mcp-title">{text.title}</h2>
          <p className="platform-description">{text.description}</p>
          <p className="mcp-path">{text.path}</p>
        </div>

        <figure
          className="mcp-terminal"
          aria-label={text.terminal.ariaLabel}
          data-testid="mcp-terminal"
        >
          <div className="mcp-terminal-chrome" aria-hidden="true">
            <span className="mcp-terminal-dots">
              <i />
              <i />
              <i />
            </span>
            <span className="mcp-terminal-label">{text.terminal.label}</span>
          </div>
          <pre className="mcp-terminal-body">
            {text.terminal.lines.map((line, index) => (
              <span
                key={`${line.role}-${index}`}
                className={`mcp-terminal-line mcp-terminal-line--${line.role}`}
              >
                {line.role === "call" ? (
                  <>
                    <span className="mcp-terminal-prompt">›</span>
                    <span className="mcp-terminal-call">{line.text}</span>
                  </>
                ) : (
                  <span className="mcp-terminal-result">{line.text}</span>
                )}
              </span>
            ))}
          </pre>
        </figure>
      </div>
    </section>
  );
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

          <p className="market-coverage">{copy.markets}</p>

          <div className="actions">
            <a className="cta-button cta-primary" href={latestReleaseUrl}>
              <img src="/apple.svg" alt="" width={15} height={15} aria-hidden="true" />
              {copy.downloadLabel}
            </a>
            <a
              className="cta-button cta-secondary"
              href="#omarchy"
              data-testid="hero-omarchy-cta"
            >
              <span className="cta-platform-dot" aria-hidden="true" />
              {copy.omarchyLabel}
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
          <div className="macos-popover" data-testid="macos-popover">
            <div className="screenshot-viewport">
              <InteractivePreview language={language} ariaLabel={copy.screenshotAlt} />
            </div>
          </div>
        </div>
      </section>

      <FeatureShowcase language={language} />

      <MCPSection language={language} />

      <OmarchySection language={language} />

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
