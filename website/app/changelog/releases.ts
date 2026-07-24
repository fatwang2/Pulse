export type Release = {
  version: string;
  date: string;
  kind: "release" | "improvement" | "fix";
  highlights: {
    zh: readonly string[];
    en: readonly string[];
  };
};

export const releases: readonly Release[] = [
  {
    version: "0.6.2",
    date: "2026-07-24",
    kind: "fix",
    highlights: {
      zh: [
        "自选分组现在可以从右键菜单直接删除，不再弹出会关闭菜单栏面板的确认窗口。",
        "删除分组时，独有标的会安全移入其他分组，持仓数据不会丢失。",
      ],
      en: [
        "Delete a watchlist directly from its context menu, without a confirmation window that closes the menu bar panel.",
        "Symbols unique to that list move safely to another list, with position data preserved.",
      ],
    },
  },
  {
    version: "0.6.1",
    date: "2026-07-24",
    kind: "fix",
    highlights: {
      zh: [
        "修复自动更新版本号，使 0.5.1 可以正确发现并安装 0.6 系列更新。",
        "包含 0.6.0 中的 Longbridge SDK、指数规范化、稳定名称与设置持久化改进。",
      ],
      en: [
        "Fixed automatic update versioning so Pulse 0.5.1 can discover and install the 0.6 series.",
        "Includes the Longbridge SDK, normalized indices, stable names, and persistent settings introduced in 0.6.0.",
      ],
    },
  },
  {
    version: "0.6.0",
    date: "2026-07-24",
    kind: "release",
    highlights: {
      zh: [
        "Longbridge 行情切换到固定版本的官方 SDK，并加强断线恢复与单标的回退。",
        "统一不同 Provider 下的指数身份、名称、搜索标签与代码映射。",
        "指数按不可交易基准处理，不再显示持仓编辑入口。",
        "标的名称遵循行情源优先级：降级不改名，更高优先级来源可以更新名称。",
        "红涨绿跌、列表指标等显示偏好现在会在重启后保留。",
        "长自选列表支持滚动，截断的标的名称可通过系统浮层查看完整内容。",
      ],
      en: [
        "Moved Longbridge market data to the pinned official SDK, with stronger recovery and per-symbol fallback.",
        "Normalized index identity, names, search labels, and symbol mapping across providers.",
        "Indices are treated as non-tradable benchmarks and no longer show position editing.",
        "Security names now follow quote-provider priority: fallback cannot downgrade them, while a higher-priority source can improve them.",
        "Display preferences such as rise/fall colors and watchlist metrics now survive restarts.",
        "Long watchlists scroll cleanly, and truncated names reveal their full value in a native tooltip.",
      ],
    },
  },
  {
    version: "0.5.1",
    date: "2026-07-21",
    kind: "fix",
    highlights: {
      zh: [
        "搜索结果会在任一有效数据源返回后立即出现，不再等待所有来源。",
        "搜索加入超时边界；快速输入时会取消旧请求，临时空结果也不再被缓存。",
      ],
      en: [
        "Search results now appear as soon as any useful source responds, without waiting for every provider.",
        "Searches now have a deadline, superseded requests cancel cleanly, and transient empty results are no longer cached.",
      ],
    },
  },
  {
    version: "0.5.0",
    date: "2026-07-21",
    kind: "release",
    highlights: {
      zh: [
        "新增多个命名自选分组，可创建、重命名、删除、拖拽排序，并用 Command-1 至 Command-9 快速切换。",
        "搜索改为并发查询数据源，结果会加入当前分组；同一标的可以出现在多个分组中。",
        "菜单栏轮播可以指定某个自选分组。",
        "Longbridge 重连与授权迁移更可靠，并提供清晰的连接、降级状态与重试入口。",
        "分享图片加入低调的 pulseticker.app 标识，并修正不同市场的成交额显示。",
      ],
      en: [
        "Added multiple named watchlists with create, rename, delete, drag reordering, and Command-1 through Command-9 shortcuts.",
        "Search now runs providers concurrently and adds results to the selected list; a symbol can belong to multiple lists.",
        "Menu bar quote rotation can target a specific watchlist.",
        "Longbridge reconnect and authorization migration are more reliable, with clearer status and retry controls.",
        "Share images now carry a quiet pulseticker.app signature, alongside corrected turnover values across markets.",
      ],
    },
  },
  {
    version: "0.4.1",
    date: "2026-07-20",
    kind: "improvement",
    highlights: {
      zh: [
        "应用内新增 Pulse 官网与 GitHub 的快捷入口。",
        "设置、搜索结果与 Longbridge 连接反馈过渡更顺滑，并遵循“减弱动态效果”设置。",
        "官网提供稳定的最新版下载地址，并展示 Pulse 使用的行情数据来源。",
      ],
      en: [
        "Added direct links to the Pulse website and GitHub from inside the app.",
        "Smoothed settings, search, and Longbridge connection transitions while respecting Reduce Motion.",
        "The website now offers a stable latest-download URL and identifies the market-data sources Pulse uses.",
      ],
    },
  },
  {
    version: "0.4.0",
    date: "2026-07-15",
    kind: "release",
    highlights: {
      zh: [
        "加密货币搜索、行情与图表切换到 Binance Spot 公共接口，并在面板打开时接收秒级 WebSocket 更新。",
        "加密货币统一使用 BTC/USDT 这类基础币/计价币格式，旧标的会自动迁移。",
        "Binance 与 Longbridge 实时流可以同时运行，各自服务加密货币与证券行情。",
        "数据源设置使用统一的状态和市场覆盖说明。",
        "新增可随时关闭的匿名使用统计，且不会上传标的、自选、持仓、搜索或凭证。",
      ],
      en: [
        "Moved crypto search, quotes, and charts to Binance Spot public APIs, with one-second WebSocket updates while the panel is open.",
        "Standardized crypto symbols as base/quote pairs such as BTC/USDT, with automatic migration.",
        "Binance and Longbridge streams can run together for crypto and securities.",
        "Unified status and market-coverage descriptions across data-source settings.",
        "Added optional anonymous product analytics that never includes symbols, watchlists, positions, searches, or credentials.",
      ],
    },
  },
  {
    version: "0.3.0",
    date: "2026-07-15",
    kind: "release",
    highlights: {
      zh: [
        "标的详情页新增分享，可生成不包含私人持仓的行情图片。",
        "自选列表、详情页和分享图片统一使用当前交易时段的一分钟趋势数据。",
        "趋势缓存在列表与详情之间共享，让不同界面尽量保持同一市场快照。",
        "实时行情状态在打开和关闭面板时保持稳定，不再闪回普通状态。",
      ],
      en: [
        "Added symbol sharing from the detail page, with private position data excluded.",
        "Watchlists, details, and shared images now use the same current-session one-minute trend data.",
        "Trend data is shared between list and detail caches to keep surfaces on the same market snapshot.",
        "Live-feed status now stays stable while opening or closing the panel.",
      ],
    },
  },
  {
    version: "0.2.0",
    date: "2026-07-14",
    kind: "release",
    highlights: {
      zh: [
        "新增 Longbridge 实时行情，可通过浏览器授权或 OpenAPI 密钥连接自己的账户；凭证只保存在本地钥匙串。",
        "支持长连接实时推送，并覆盖美股夜盘的独立状态与价格。",
        "Tencent、Yahoo 与 Longbridge 可以分别设置刷新周期，并只在对应市场开盘时轮询。",
        "重做数据源详情页，清晰展示连接状态、覆盖市场、刷新方式与时效。",
        "自选列表底部开始展示“实时推送”等行情健康状态。",
      ],
      en: [
        "Added Longbridge real-time quotes through browser authorization or OpenAPI keys, with credentials kept in the local Keychain.",
        "Added persistent live streaming, including a dedicated US overnight state and price.",
        "Tencent, Yahoo, and Longbridge now have independent refresh intervals and market-hours-aware polling.",
        "Redesigned source detail pages to explain connection, coverage, refresh mode, and freshness.",
        "The watchlist footer now reports feed health such as “Streaming live.”",
      ],
    },
  },
  {
    version: "0.1.6",
    date: "2026-07-11",
    kind: "improvement",
    highlights: {
      zh: [
        "详情统计用振幅替代成交额，更直观地显示当日高低波动范围。",
        "价格更新加入随涨跌方向滚动的数字动画，页面、按钮与周期切换也更加顺滑。",
        "所有动画遵循 macOS 的“减弱动态效果”设置。",
        "修复详情标题截断，并改善较长本地化文案下的周期选择器布局。",
      ],
      en: [
        "Replaced turnover with amplitude in detail statistics to show the day’s high–low range more clearly.",
        "Added directional rolling digits for price changes and smoother page, button, and period transitions.",
        "All motion now respects the macOS Reduce Motion setting.",
        "Fixed detail-title truncation and improved the period picker for longer localizations.",
      ],
    },
  },
  {
    version: "0.1.5",
    date: "2026-07-10",
    kind: "release",
    highlights: {
      zh: [
        "可以把品牌化、适合手机查看的自选列表图片直接复制到剪贴板。",
        "分享图片会跟随当前列表指标，并根据自选数量自动调整布局。",
        "A 股分时优先使用腾讯实时数据，并以 Yahoo 作为回退和历史 K 线来源。",
        "复制成功提示与市场状态可以同时清晰显示。",
      ],
      en: [
        "Copy a branded, mobile-friendly watchlist image directly to the clipboard.",
        "Share images now follow the selected metric and adapt to watchlist length.",
        "China A-share intraday data now prefers realtime Tencent data, with Yahoo fallback and historical candles.",
        "Copy confirmation now appears without hiding market status.",
      ],
    },
  },
  {
    version: "0.1.4",
    date: "2026-07-09",
    kind: "release",
    highlights: {
      zh: [
        "新增简体中文与英文，支持跟随系统语言或手动切换。",
        "通过 Yahoo Finance 增加加密货币搜索、行情与分时图支持。",
        "为搜索、行情和 K 线加入缓存与请求节流，降低重复请求和限流风险。",
        "搜索输入与加载状态更稳定，行情详情也会分别显示时效、来源与市场时间。",
      ],
      en: [
        "Added English and Simplified Chinese with system-language detection and manual switching.",
        "Added crypto search, quotes, and intraday charts through Yahoo Finance.",
        "Added caching and request pacing for search, quotes, and candles.",
        "Improved search focus and loading states, with separate freshness, source, and market-time metadata.",
      ],
    },
  },
  {
    version: "0.1.3",
    date: "2026-07-08",
    kind: "improvement",
    highlights: {
      zh: ["加入正式的 Pulse macOS 应用图标。"],
      en: ["Introduced the official Pulse macOS app icon."],
    },
  },
  {
    version: "0.1.2",
    date: "2026-07-08",
    kind: "fix",
    highlights: {
      zh: [
        "新增适合首次安装的 DMG 安装包。",
        "修复沙盒环境下的 Sparkle 自动更新支持。",
      ],
      en: [
        "Added a DMG installer for first-time installation.",
        "Fixed Sparkle automatic updates for sandboxed builds.",
      ],
    },
  },
  {
    version: "0.1.1",
    date: "2026-07-08",
    kind: "improvement",
    highlights: {
      zh: [
        "完善首次公开预览的应用截图与安装说明，让菜单栏自选列表更容易被了解。",
      ],
      en: [
        "Refined the first public preview with a clearer menu bar watchlist screenshot and installation guidance.",
      ],
    },
  },
  {
    version: "0.1.0",
    date: "2026-07-08",
    kind: "release",
    highlights: {
      zh: [
        "Pulse 首次公开发布：在 macOS 菜单栏查看美股、港股、A 股、指数与 ETF。",
        "支持自选列表、菜单栏行情轮播、持仓与盈亏、详情统计、分时图和 K 线。",
        "通过腾讯与 Yahoo Finance 提供行情路由与自动回退。",
        "根据交易时段刷新并在本地保存自选、持仓与设置。",
      ],
      en: [
        "Pulse launched publicly as a macOS menu bar tracker for US, Hong Kong, and China stocks, indices, and ETFs.",
        "Included watchlists, menu bar quote rotation, positions and P&L, detail statistics, intraday charts, and candles.",
        "Added Tencent and Yahoo Finance provider routing with automatic fallback.",
        "Added market-hours-aware refresh and local persistence for watchlists, positions, and settings.",
      ],
    },
  },
];
