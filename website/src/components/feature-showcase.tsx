import { useEffect, useRef, useState } from "react";

type Language = "zh" | "en";

const riseColor = "#ff414b";
const fallColor = "#00a962";
const wingLine = "#9aa1a9";
const gridLine = "rgba(120, 128, 138, 0.2)";

const copy = {
  zh: {
    overline: "功能亮点",
    title: "把专业行情装进菜单栏。",
    subtitle:
      "蜡烛图、盘前盘后、分享卡与多分组自选——每个细节都为快速看盘设计。",
    candles: {
      title: "真正的蜡烛图",
      description:
        "标准蜡烛与成交量严格对齐，支持滚轮缩放与横向浏览；新增 5 分、15 分、30 分与 1 小时周期。",
      hint: "点击切换周期",
      chartLabel: "蜡烛图演示",
    },
    extended: {
      title: "盘前盘后行情",
      description:
        "美股分时覆盖美东 04:00–20:00，盘前盘后以灰色翼区呈现，9:30 与 16:00 边界清晰可辨，可在设置中关闭。",
      chartLabel: "盘前盘后分时演示，灰色翼区为延长时段",
    },
    share: {
      title: "一键分享卡",
      description:
        "自选列表 1:1 卡片与个股 16:9 海报，跟随系统深浅色与红涨绿跌设置；K 线分享精确还原屏幕上的可见区间。",
      listCardTitle: "核心自选",
      listCardDate: "07-30 收盘",
      symbolName: "腾讯控股",
      symbolMeta: "700 · HK",
      rangeLow: "459.20",
      rangeHigh: "470.80",
      demoLabel: "分享卡样式演示",
    },
    search: {
      title: "搜索与多分组",
      description:
        "⌘F 即刻搜索，未关注的标的也能直接打开详情；自选按需分组管理，⌘1–9 一键切换。",
      placeholder: "搜索代码或名称…",
      recentLabel: "最近搜索",
      lists: ["全部", "持仓", "关注"],
      demoLabel: "搜索面板与分组演示",
    },
  },
  en: {
    overline: "Feature highlights",
    title: "A full quote terminal, in your menu bar.",
    subtitle:
      "Candlesticks, extended hours, share cards, and multi-list watchlists—every detail built for a quick read.",
    candles: {
      title: "True candlesticks",
      description:
        "Candles with precisely aligned volume, wheel zoom, and horizontal browsing—plus 5-minute, 15-minute, 30-minute, and 1-hour resolutions.",
      hint: "Click to switch resolution",
      chartLabel: "Candlestick chart demo",
    },
    extended: {
      title: "Extended hours built in",
      description:
        "US intraday covers 04:00–20:00 ET. Pre- and post-market sessions render as gray wings with clear 9:30 / 16:00 boundaries—toggle them in Settings.",
      chartLabel: "Extended-hours intraday demo with gray session wings",
    },
    share: {
      title: "Share cards in one click",
      description:
        "A 1:1 watchlist card and a 16:9 symbol poster that follow your appearance and rise/fall colors. K-line shares match the visible window exactly.",
      listCardTitle: "Core watchlist",
      listCardDate: "Jul 30 close",
      symbolName: "Tencent",
      symbolMeta: "700 · HK",
      rangeLow: "459.20",
      rangeHigh: "470.80",
      demoLabel: "Share card style demo",
    },
    search: {
      title: "Search & lists",
      description:
        "Hit ⌘F to search and open any symbol—watched or not. Organize your watchlist into lists and jump with ⌘1–9.",
      placeholder: "Search symbol or name…",
      recentLabel: "Recent",
      lists: ["All", "Positions", "Watching"],
      demoLabel: "Search panel and list demo",
    },
  },
} as const;

function mulberry32(seed: number) {
  let state = seed >>> 0;
  return () => {
    state |= 0;
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function fitCanvas(canvas: HTMLCanvasElement) {
  const rect = canvas.getBoundingClientRect();
  const width = Math.max(1, rect.width);
  const height = Math.max(1, rect.height);
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(width * ratio);
  canvas.height = Math.round(height * ratio);
  const context = canvas.getContext("2d");
  context?.setTransform(ratio, 0, 0, ratio, 0, 0);
  return { context, width, height };
}

type Candle = {
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
};

function makeCandles(
  seed: number,
  count: number,
  volatility: number,
  drift: number,
): Candle[] {
  const random = mulberry32(seed);
  const candles: Candle[] = [];
  let price = 100;

  for (let index = 0; index < count; index += 1) {
    const open = price;
    const change = (random() - 0.48) * 2 * volatility + drift;
    const close = open * (1 + change);
    const upperWick = Math.abs(change) * 0.6 * random() + volatility * 0.35 * random();
    const lowerWick = Math.abs(change) * 0.6 * random() + volatility * 0.35 * random();
    const high = Math.max(open, close) * (1 + upperWick);
    const low = Math.min(open, close) * (1 - lowerWick);
    const volume = 0.35 + random() * 0.65 + Math.abs(change) / volatility * 0.2;
    candles.push({ open, high, low, close, volume });
    price = close;
  }

  return candles;
}

const candleResolutions = [
  { id: "5m", label: { zh: "5分", en: "5m" }, seed: 11, count: 46, volatility: 0.006, drift: 0.0011 },
  { id: "15m", label: { zh: "15分", en: "15m" }, seed: 23, count: 42, volatility: 0.009, drift: -0.0008 },
  { id: "30m", label: { zh: "30分", en: "30m" }, seed: 37, count: 40, volatility: 0.011, drift: 0.0015 },
  { id: "1h", label: { zh: "1时", en: "1h" }, seed: 53, count: 38, volatility: 0.014, drift: 0.0019 },
  { id: "1d", label: { zh: "日K", en: "1D" }, seed: 71, count: 34, volatility: 0.024, drift: 0.0028 },
] as const;

const candleData = new Map(
  candleResolutions.map((resolution) => [
    resolution.id,
    makeCandles(resolution.seed, resolution.count, resolution.volatility, resolution.drift),
  ]),
);

function drawCandles(
  context: CanvasRenderingContext2D,
  width: number,
  height: number,
  candles: Candle[],
  progress: number,
) {
  context.clearRect(0, 0, width, height);

  const priceTop = 4;
  const priceBottom = height * 0.74;
  const volumeTop = height * 0.8;
  const volumeBottom = height - 3;

  let low = Infinity;
  let high = -Infinity;
  let maxVolume = 0;
  for (const candle of candles) {
    low = Math.min(low, candle.low);
    high = Math.max(high, candle.high);
    maxVolume = Math.max(maxVolume, candle.volume);
  }
  const spread = Math.max(1e-6, high - low);
  const priceY = (value: number) =>
    priceTop + ((high - value) / spread) * (priceBottom - priceTop);

  context.setLineDash([3, 3]);
  context.strokeStyle = gridLine;
  context.lineWidth = 0.75;
  for (const ratio of [0.25, 0.5, 0.75]) {
    const y = priceTop + (priceBottom - priceTop) * ratio;
    context.beginPath();
    context.moveTo(0, y);
    context.lineTo(width, y);
    context.stroke();
  }
  context.setLineDash([]);

  const slot = width / candles.length;
  const bodyWidth = Math.max(2, slot * 0.58);
  const visibleCount = Math.max(2, Math.ceil(candles.length * progress));

  candles.slice(0, visibleCount).forEach((candle, index) => {
    const centerX = slot * index + slot / 2;
    const up = candle.close >= candle.open;
    const color = up ? riseColor : fallColor;

    context.strokeStyle = color;
    context.lineWidth = 1;
    context.beginPath();
    context.moveTo(centerX, priceY(candle.high));
    context.lineTo(centerX, priceY(candle.low));
    context.stroke();

    const bodyTop = priceY(Math.max(candle.open, candle.close));
    const bodyHeight = Math.max(
      1.4,
      priceY(Math.min(candle.open, candle.close)) - bodyTop,
    );
    context.fillStyle = color;
    context.fillRect(centerX - bodyWidth / 2, bodyTop, bodyWidth, bodyHeight);

    const volumeHeight = Math.max(
      1,
      (candle.volume / maxVolume) * (volumeBottom - volumeTop),
    );
    context.fillStyle = up ? `${riseColor}3d` : `${fallColor}3d`;
    context.fillRect(
      centerX - bodyWidth / 2,
      volumeBottom - volumeHeight,
      bodyWidth,
      volumeHeight,
    );
  });

  if (progress === 1) {
    const last = candles[candles.length - 1];
    const y = priceY(last.close);
    context.setLineDash([2, 3]);
    context.strokeStyle = `${last.close >= last.open ? riseColor : fallColor}66`;
    context.lineWidth = 0.9;
    context.beginPath();
    context.moveTo(0, y);
    context.lineTo(width, y);
    context.stroke();
    context.setLineDash([]);
  }
}

function CandleDemo({ language }: { language: Language }) {
  const text = copy[language].candles;
  const [resolutionId, setResolutionId] =
    useState<(typeof candleResolutions)[number]["id"]>("1d");
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const candles = candleData.get(resolutionId);
    if (!candles) return;

    let frame = 0;
    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const startedAt = performance.now();
    const duration = reducedMotion ? 0 : 430;

    function render(now: number) {
      if (!canvas) return;
      const { context, width, height } = fitCanvas(canvas);
      if (!context) return;
      const progress =
        duration === 0 ? 1 : Math.min(1, (now - startedAt) / duration);
      if (!candles) return;
      drawCandles(context, width, height, candles, progress);
      if (progress < 1) frame = requestAnimationFrame(render);
    }

    frame = requestAnimationFrame(render);
    const observer = new ResizeObserver(() => {
      frame = requestAnimationFrame(render);
    });
    observer.observe(canvas);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [resolutionId]);

  return (
    <div className="feature-demo candle-demo" data-testid="candle-demo">
      <div className="candle-res" role="group" aria-label={text.hint}>
        {candleResolutions.map((resolution) => (
          <button
            key={resolution.id}
            type="button"
            className={resolution.id === resolutionId ? "active" : undefined}
            aria-pressed={resolution.id === resolutionId}
            onClick={() => setResolutionId(resolution.id)}
          >
            {resolution.label[language]}
          </button>
        ))}
        <span className="candle-hint">{text.hint}</span>
      </div>
      <canvas
        ref={canvasRef}
        className="candle-canvas"
        role="img"
        aria-label={text.chartLabel}
      />
    </div>
  );
}

const extendedHoursSeries = (() => {
  const random = mulberry32(97);
  const total = 176;
  const preEnd = Math.round(total * (5.5 / 16));
  const regularEnd = Math.round(total * (12 / 16));
  const series: number[] = [];
  let value = 50;

  for (let index = 0; index < total; index += 1) {
    let step: number;
    if (index < preEnd) {
      step = (random() - 0.52) * 1.1;
    } else if (index < regularEnd) {
      step = (random() - 0.42) * 2.3;
    } else {
      step = (random() - 0.5) * 0.9;
    }
    value = Math.min(96, Math.max(6, value + step));
    series.push(value);
  }

  return { series, preEnd, regularEnd };
})();

function drawExtendedHours(
  context: CanvasRenderingContext2D,
  width: number,
  height: number,
) {
  context.clearRect(0, 0, width, height);

  const { series, preEnd, regularEnd } = extendedHoursSeries;
  const chartTop = 6;
  const chartBottom = height - 22;
  const preX = (preEnd / series.length) * width;
  const regularX = (regularEnd / series.length) * width;

  context.fillStyle = "rgba(120, 128, 138, 0.07)";
  context.fillRect(0, 0, preX, chartBottom + 8);
  context.fillRect(regularX, 0, width - regularX, chartBottom + 8);

  context.strokeStyle = "rgba(90, 98, 108, 0.25)";
  context.lineWidth = 1;
  for (const x of [preX, regularX]) {
    context.beginPath();
    context.moveTo(x, 0);
    context.lineTo(x, chartBottom + 8);
    context.stroke();
  }

  let min = Infinity;
  let max = -Infinity;
  for (const value of series) {
    min = Math.min(min, value);
    max = Math.max(max, value);
  }
  const spread = Math.max(1, max - min);
  const pointX = (index: number) =>
    (index / (series.length - 1)) * width;
  const pointY = (value: number) =>
    chartTop + ((max - value) / spread) * (chartBottom - chartTop);

  const baseline = pointY(series[0]);
  context.setLineDash([3, 3]);
  context.strokeStyle = gridLine;
  context.lineWidth = 0.75;
  context.beginPath();
  context.moveTo(0, baseline);
  context.lineTo(width, baseline);
  context.stroke();
  context.setLineDash([]);

  const segments: Array<{ from: number; to: number; color: string }> = [
    { from: 0, to: preEnd, color: wingLine },
    { from: preEnd, to: regularEnd, color: riseColor },
    { from: regularEnd, to: series.length - 1, color: wingLine },
  ];

  for (const segment of segments) {
    context.beginPath();
    for (let index = segment.from; index <= segment.to; index += 1) {
      const x = pointX(index);
      const y = pointY(series[index]);
      if (index === segment.from) context.moveTo(x, y);
      else context.lineTo(x, y);
    }
    context.strokeStyle = segment.color;
    context.lineWidth = 1.4;
    context.lineCap = "round";
    context.lineJoin = "round";
    context.stroke();
  }

  const end = {
    x: pointX(series.length - 1),
    y: pointY(series[series.length - 1]),
  };
  context.beginPath();
  context.arc(Math.min(end.x, width - 3), end.y, 2.4, 0, Math.PI * 2);
  context.fillStyle = wingLine;
  context.fill();

  context.fillStyle = "#a0a5ab";
  context.font =
    '9px ui-monospace, "SF Mono", Menlo, monospace';
  context.textBaseline = "alphabetic";
  const labelY = height - 7;
  context.textAlign = "left";
  context.fillText("04:00", 2, labelY);
  context.textAlign = "center";
  context.fillText("09:30", preX, labelY);
  context.fillText("16:00", regularX, labelY);
  context.textAlign = "right";
  context.fillText("20:00", width - 2, labelY);
}

function ExtendedHoursDemo({ language }: { language: Language }) {
  const text = copy[language].extended;
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let frame = 0;

    function render() {
      if (!canvas) return;
      const { context, width, height } = fitCanvas(canvas);
      if (!context) return;
      drawExtendedHours(context, width, height);
    }

    frame = requestAnimationFrame(render);
    const observer = new ResizeObserver(() => {
      frame = requestAnimationFrame(render);
    });
    observer.observe(canvas);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, []);

  return (
    <div className="feature-demo" data-testid="extended-hours-demo">
      <canvas
        ref={canvasRef}
        className="extended-canvas"
        role="img"
        aria-label={text.chartLabel}
      />
    </div>
  );
}

const shareListRows = [
  { name: "NVDA", spark: "M0 14 L6 12 L12 13 L18 9 L24 10 L30 6 L36 7 L42 3", change: "+2.41%", positive: true },
  { name: "700", spark: "M0 6 L6 8 L12 7 L18 10 L24 9 L30 12 L36 11 L42 13", change: "-0.34%", positive: false },
  { name: "BTC-USD", spark: "M0 12 L6 13 L12 10 L18 11 L24 7 L30 8 L36 5 L42 6", change: "+0.97%", positive: true },
] as const;

function ShareDemo({ language }: { language: Language }) {
  const text = copy[language].share;

  return (
    <div
      className="feature-demo share-demo"
      data-testid="share-demo"
      role="img"
      aria-label={text.demoLabel}
    >
      <div className="share-card share-card--list" aria-hidden="true">
        <header>
          <strong>{text.listCardTitle}</strong>
          <span>{text.listCardDate}</span>
        </header>
        <ul>
          {shareListRows.map((row) => (
            <li key={row.name}>
              <span className="share-row-name">{row.name}</span>
              <svg viewBox="0 0 42 16" preserveAspectRatio="none" aria-hidden="true">
                <path
                  d={row.spark}
                  fill="none"
                  stroke={row.positive ? riseColor : fallColor}
                  strokeWidth="1.4"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              </svg>
              <span
                className={`share-row-change ${row.positive ? "positive" : "negative"}`}
              >
                {row.change}
              </span>
            </li>
          ))}
        </ul>
        <footer>pulseticker.app</footer>
      </div>

      <div className="share-card share-card--symbol" aria-hidden="true">
        <header>
          <div>
            <strong>{text.symbolName}</strong>
            <span>{text.symbolMeta}</span>
          </div>
          <div className="share-symbol-price">
            <strong>468.00</strong>
            <span className="negative">-0.34%</span>
          </div>
        </header>
        <svg
          className="share-symbol-chart"
          viewBox="0 0 100 30"
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <path
            d="M0 20 L8 18 L16 21 L24 16 L32 17 L40 12 L48 14 L56 9 L64 11 L72 7 L80 9 L88 5 L100 8 L100 30 L0 30 Z"
            fill="rgba(0, 169, 98, 0.08)"
          />
          <path
            d="M0 20 L8 18 L16 21 L24 16 L32 17 L40 12 L48 14 L56 9 L64 11 L72 7 L80 9 L88 5 L100 8"
            fill="none"
            stroke={fallColor}
            strokeWidth="1.1"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
        <div className="share-range">
          <span>{text.rangeLow}</span>
          <div className="share-range-bar">
            <i style={{ left: "62%" }} />
          </div>
          <span>{text.rangeHigh}</span>
        </div>
        <footer>
          <span className="share-brand">● Pulse</span>
          <span>pulseticker.app</span>
        </footer>
      </div>
    </div>
  );
}

const searchResults = [
  {
    symbol: "NVDA",
    name: { zh: "英伟达", en: "NVIDIA Corp." },
    market: "us",
    marketLabel: "US",
    price: "183.24",
    change: "+2.41%",
    positive: true,
  },
  {
    symbol: "700",
    name: { zh: "腾讯控股", en: "Tencent Holdings" },
    market: "hk",
    marketLabel: "HK",
    price: "468.00",
    change: "-0.34%",
    positive: false,
  },
  {
    symbol: "BTC-USD",
    name: { zh: "比特币", en: "Bitcoin USD" },
    market: "crypto",
    marketLabel: "Crypto",
    price: "63797.28",
    change: "+0.97%",
    positive: true,
  },
] as const;

function SearchDemo({ language }: { language: Language }) {
  const text = copy[language].search;

  return (
    <div
      className="feature-demo search-demo"
      data-testid="search-demo"
      role="img"
      aria-label={text.demoLabel}
    >
      <div className="search-panel" aria-hidden="true">
        <div className="search-input">
          <svg viewBox="0 0 14 14" aria-hidden="true">
            <circle cx="6" cy="6" r="4.4" fill="none" stroke="currentColor" strokeWidth="1.4" />
            <path d="M9.4 9.4 L12.6 12.6" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
          </svg>
          <span>{text.placeholder}</span>
          <kbd>⌘F</kbd>
        </div>
        <div className="search-recent">
          <span>{text.recentLabel}</span>
          <i>NVDA</i>
          <i>700</i>
          <i>BTC-USD</i>
        </div>
        <ul className="search-results">
          {searchResults.map((result) => (
            <li key={result.symbol}>
              <span className="search-result-title">
                <strong>{result.name[language]}</strong>
                <span>
                  <span className={`preview-market preview-market-${result.market}`}>
                    {result.marketLabel}
                  </span>
                  {result.symbol}
                </span>
              </span>
              <span className="search-result-quote">
                <strong>{result.price}</strong>
                <span className={result.positive ? "positive" : "negative"}>
                  {result.change}
                </span>
              </span>
              <span className="search-result-add">+</span>
            </li>
          ))}
        </ul>
      </div>
      <div className="search-lists" aria-hidden="true">
        {text.lists.map((list, index) => (
          <span
            key={list}
            className={index === 0 ? "search-list active" : "search-list"}
          >
            {list}
            <kbd>⌘{index + 1}</kbd>
          </span>
        ))}
      </div>
    </div>
  );
}

export function FeatureShowcase({ language }: { language: Language }) {
  const text = copy[language];

  return (
    <section
      className="features shell"
      aria-labelledby="features-title"
      data-testid="feature-showcase"
    >
      <div className="features-heading">
        <p className="overline">{text.overline}</p>
        <h2 id="features-title">{text.title}</h2>
        <p>{text.subtitle}</p>
      </div>

      <div className="features-grid">
        <article className="feature-card feature-card--candles">
          <div className="feature-card-copy">
            <h3>{text.candles.title}</h3>
            <p>{text.candles.description}</p>
          </div>
          <CandleDemo language={language} />
        </article>

        <article className="feature-card feature-card--extended">
          <div className="feature-card-copy">
            <h3>{text.extended.title}</h3>
            <p>{text.extended.description}</p>
          </div>
          <ExtendedHoursDemo language={language} />
        </article>

        <article className="feature-card feature-card--share">
          <div className="feature-card-copy">
            <h3>{text.share.title}</h3>
            <p>{text.share.description}</p>
          </div>
          <ShareDemo language={language} />
        </article>

        <article className="feature-card feature-card--search">
          <div className="feature-card-copy">
            <h3>{text.search.title}</h3>
            <p>{text.search.description}</p>
          </div>
          <SearchDemo language={language} />
        </article>
      </div>
    </section>
  );
}
