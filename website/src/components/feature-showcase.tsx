import { type PointerEvent, useEffect, useRef, useState } from "react";

type Language = "zh" | "en";

const riseColor = "#ff414b";
const fallColor = "#00a962";
const wingLine = "#9aa1a9";
const gridLine = "rgba(120, 128, 138, 0.2)";

const copy = {
  zh: {
    title: "把专业行情装进菜单栏。",
    subtitle:
      "蜡烛图、盘前盘后、持仓盈亏与标签分组——每个细节都为快速看盘设计。",
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
      hint: "悬停查看时间与价格",
      chartLabel: "盘前盘后分时演示，灰色翼区为延长时段，悬停显示十字线与对应时间价格",
    },
    positions: {
      title: "持仓盈亏，一眼可见",
      description:
        "为标的录入成本与数量后，点击金额就能在涨跌幅、今日盈亏与持仓盈亏之间切换整列指标，偏好在重启后保留。",
      modeLabel: "当前指标",
      hint: "点击金额切换指标",
      modes: { change: "涨跌幅", today: "今日盈亏", total: "持仓盈亏" },
    },
    lists: {
      title: "标签分组管理自选",
      description:
        "自选可整理进多个命名分组，顶部标签栏一键切换，支持拖拽排序与 ⌘1–9 快捷键；菜单栏轮播也能只跟随指定分组。",
      hint: "点击标签切换分组",
      tabsLabel: "切换演示分组",
    },
  },
  en: {
    title: "A full quote terminal, in your menu bar.",
    subtitle:
      "Candlesticks, extended hours, position P&L, and multi-list watchlists—every detail built for a quick read.",
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
      hint: "Hover for time and price",
      chartLabel:
        "Extended-hours intraday demo with gray session wings; hover shows a crosshair with the time and price",
    },
    positions: {
      title: "Position P&L at a glance",
      description:
        "Add cost and quantity, then click any value to flip the whole list between change, today's P&L, and total P&L—your metric choice sticks across restarts.",
      modeLabel: "Metric",
      hint: "Click a value to switch metric",
      modes: { change: "Change", today: "Today P&L", total: "Position P&L" },
    },
    lists: {
      title: "Multi-list watchlists",
      description:
        "Organize symbols into named lists and switch from the list bar on top—drag to reorder, jump with ⌘1–9, and point the menu-bar ticker at any list.",
      hint: "Click a tab to switch lists",
      tabsLabel: "Switch demo list",
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
  { id: "1w", label: { zh: "周K", en: "1W" }, seed: 89, count: 32, volatility: 0.032, drift: 0.0042 },
  { id: "1mo", label: { zh: "月K", en: "1M" }, seed: 103, count: 30, volatility: 0.042, drift: 0.007 },
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

function extendedHoursTime(index: number) {
  const minutes = Math.round(
    4 * 60 + (index / (extendedHoursSeries.series.length - 1)) * 16 * 60,
  );
  const hours = Math.floor(minutes / 60);
  const minute = minutes % 60;
  return `${hours.toString().padStart(2, "0")}:${minute.toString().padStart(2, "0")}`;
}

function extendedHoursPrice(value: number) {
  return 180 + value * 0.1;
}

function drawExtendedHours(
  context: CanvasRenderingContext2D,
  width: number,
  height: number,
  hoverIndex: number | null,
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

  if (hoverIndex === null) return;

  const index = Math.max(0, Math.min(series.length - 1, hoverIndex));
  const x = pointX(index);
  const y = pointY(series[index]);
  const detail = `${extendedHoursTime(index)}  $${extendedHoursPrice(series[index]).toFixed(2)}`;

  context.save();
  context.setLineDash([3, 3]);
  context.strokeStyle = "rgba(62, 68, 76, 0.48)";
  context.lineWidth = 0.8;
  context.beginPath();
  context.moveTo(x, chartTop);
  context.lineTo(x, chartBottom);
  context.moveTo(0, y);
  context.lineTo(width, y);
  context.stroke();
  context.setLineDash([]);

  context.beginPath();
  context.arc(x, y, 3, 0, Math.PI * 2);
  context.fillStyle = "#ffffff";
  context.fill();
  context.strokeStyle = "#343940";
  context.lineWidth = 1.4;
  context.stroke();

  context.font = '10px ui-monospace, "SF Mono", Menlo, monospace';
  const tooltipWidth = context.measureText(detail).width + 14;
  const tooltipHeight = 24;
  const tooltipX =
    x + tooltipWidth + 10 <= width ? x + 8 : Math.max(2, x - tooltipWidth - 8);
  const tooltipY = Math.max(
    3,
    Math.min(chartBottom - tooltipHeight - 3, y - tooltipHeight - 8),
  );

  context.fillStyle = "rgba(37, 38, 40, 0.94)";
  context.beginPath();
  context.roundRect(tooltipX, tooltipY, tooltipWidth, tooltipHeight, 6);
  context.fill();
  context.fillStyle = "#ffffff";
  context.textAlign = "left";
  context.textBaseline = "middle";
  context.fillText(detail, tooltipX + 7, tooltipY + tooltipHeight / 2);
  context.restore();
}

function ExtendedHoursDemo({ language }: { language: Language }) {
  const text = copy[language].extended;
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const hoverIndexRef = useRef<number | null>(null);
  const renderRef = useRef<() => void>(() => undefined);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let frame = 0;

    function render() {
      if (!canvas) return;
      const { context, width, height } = fitCanvas(canvas);
      if (!context) return;
      drawExtendedHours(context, width, height, hoverIndexRef.current);
    }

    renderRef.current = render;
    frame = requestAnimationFrame(render);
    const observer = new ResizeObserver(() => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(render);
    });
    observer.observe(canvas);

    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      renderRef.current = () => undefined;
    };
  }, []);

  function updateCrosshair(event: PointerEvent<HTMLCanvasElement>) {
    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    const nextIndex = Math.round(
      ratio * (extendedHoursSeries.series.length - 1),
    );
    if (nextIndex === hoverIndexRef.current) return;
    hoverIndexRef.current = nextIndex;
    renderRef.current();
  }

  function clearCrosshair() {
    if (hoverIndexRef.current === null) return;
    hoverIndexRef.current = null;
    renderRef.current();
  }

  return (
    <div className="feature-demo" data-testid="extended-hours-demo">
      <div className="extended-hint">{text.hint}</div>
      <canvas
        ref={canvasRef}
        className="extended-canvas"
        role="img"
        aria-label={text.chartLabel}
        onPointerMove={updateCrosshair}
        onPointerLeave={clearCrosshair}
      />
    </div>
  );
}

type PositionMetric = "change" | "today" | "total";

const positionMetricOrder: PositionMetric[] = ["change", "today", "total"];

type PositionRow = {
  symbol: string;
  name: string;
  market: string;
  marketLabel: string;
  price: string;
  change: string;
  today: string;
  total: string;
};

const positionRowsByLanguage: Record<Language, readonly PositionRow[]> = {
  zh: [
    { symbol: "688018", name: "乐鑫科技", market: "sh", marketLabel: "沪", price: "129.39", change: "+6.67%", today: "+¥1,624", total: "+¥8,960" },
    { symbol: "700", name: "腾讯控股", market: "hk", marketLabel: "港股", price: "468.00", change: "-0.34%", today: "-HK$136", total: "+HK$6,240" },
    { symbol: "BTC-USD", name: "比特币", market: "crypto", marketLabel: "加密", price: "63797.28", change: "+0.97%", today: "+$187.20", total: "+$3,482" },
  ],
  en: [
    { symbol: "NVDA", name: "NVIDIA Corp.", market: "us", marketLabel: "US", price: "183.24", change: "+2.41%", today: "+$412.80", total: "+$5,214" },
    { symbol: "TSLA", name: "Tesla, Inc.", market: "us", marketLabel: "US", price: "412.66", change: "-1.85%", today: "-$318.40", total: "+$2,905" },
    { symbol: "BTC-USD", name: "Bitcoin USD", market: "crypto", marketLabel: "Crypto", price: "63797.28", change: "+0.97%", today: "+$187.20", total: "+$3,482" },
  ],
};

function PositionsDemo({ language }: { language: Language }) {
  const text = copy[language].positions;
  const positionRows = positionRowsByLanguage[language];
  const [metric, setMetric] = useState<PositionMetric>("total");

  function cycleMetric() {
    setMetric(
      (current) =>
        positionMetricOrder[
          (positionMetricOrder.indexOf(current) + 1) % positionMetricOrder.length
        ],
    );
  }

  return (
    <div className="feature-demo positions-demo" data-testid="positions-demo">
      <div className="positions-mode">
        <span>
          {text.modeLabel}
          <strong key={metric}>{text.modes[metric]}</strong>
        </span>
        <span className="positions-hint">{text.hint}</span>
      </div>
      <ul className="positions-list">
        {positionRows.map((row) => {
          const value = row[metric];
          const positive = value.startsWith("+");
          return (
            <li key={row.symbol}>
              <span className="position-row-title">
                <strong>{row.name}</strong>
                <span>
                  <span className={`preview-market preview-market-${row.market}`}>
                    {row.marketLabel}
                  </span>
                  {row.symbol}
                </span>
              </span>
              <button
                type="button"
                className="position-row-value"
                aria-label={`${text.hint}: ${row.name}, ${row.price}, ${text.modes[metric]} ${value}`}
                onClick={cycleMetric}
              >
                <strong>{row.price}</strong>
                <span
                  key={`${row.symbol}-${metric}`}
                  className={`preview-metric ${positive ? "positive" : "negative"}`}
                >
                  {value}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

type DemoListId = "core" | "us" | "crypto";

const demoLists = [
  { id: "core", label: { zh: "核心", en: "Core" } },
  { id: "us", label: { zh: "美股", en: "US" } },
  { id: "crypto", label: { zh: "加密", en: "Crypto" } },
] as const;

type ListRow = {
  symbol: string;
  name: string;
  market: string;
  marketLabel: string;
  price: string;
  change: string;
};

const listRowsByLanguage: Record<Language, Record<DemoListId, readonly ListRow[]>> = {
  zh: {
    core: [
      { symbol: "700", name: "腾讯控股", market: "hk", marketLabel: "港股", price: "468.00", change: "-0.34%" },
      { symbol: "688018", name: "乐鑫科技", market: "sh", marketLabel: "沪", price: "129.39", change: "+6.67%" },
      { symbol: "BTC-USD", name: "比特币", market: "crypto", marketLabel: "加密", price: "63797.28", change: "+0.97%" },
    ],
    us: [
      { symbol: "NVDA", name: "英伟达", market: "us", marketLabel: "美股", price: "183.24", change: "+2.41%" },
      { symbol: "AAPL", name: "苹果", market: "us", marketLabel: "美股", price: "229.35", change: "+0.58%" },
      { symbol: "ONDS", name: "Ondas", market: "us", marketLabel: "美股", price: "7.67", change: "+0.26%" },
    ],
    crypto: [
      { symbol: "BTC-USD", name: "比特币", market: "crypto", marketLabel: "加密", price: "63797.28", change: "+0.97%" },
      { symbol: "ETH-USD", name: "以太坊", market: "crypto", marketLabel: "加密", price: "3290.12", change: "+1.85%" },
      { symbol: "SOL-USD", name: "索拉纳", market: "crypto", marketLabel: "加密", price: "186.42", change: "-1.24%" },
    ],
  },
  en: {
    core: [
      { symbol: "NVDA", name: "NVIDIA Corp.", market: "us", marketLabel: "US", price: "183.24", change: "+2.41%" },
      { symbol: "TSLA", name: "Tesla, Inc.", market: "us", marketLabel: "US", price: "412.66", change: "-1.85%" },
      { symbol: "BTC-USD", name: "Bitcoin USD", market: "crypto", marketLabel: "Crypto", price: "63797.28", change: "+0.97%" },
    ],
    us: [
      { symbol: "NVDA", name: "NVIDIA Corp.", market: "us", marketLabel: "US", price: "183.24", change: "+2.41%" },
      { symbol: "AAPL", name: "Apple Inc.", market: "us", marketLabel: "US", price: "229.35", change: "+0.58%" },
      { symbol: "ONDS", name: "Ondas Inc.", market: "us", marketLabel: "US", price: "7.67", change: "+0.26%" },
    ],
    crypto: [
      { symbol: "BTC-USD", name: "Bitcoin USD", market: "crypto", marketLabel: "Crypto", price: "63797.28", change: "+0.97%" },
      { symbol: "ETH-USD", name: "Ethereum USD", market: "crypto", marketLabel: "Crypto", price: "3290.12", change: "+1.85%" },
      { symbol: "SOL-USD", name: "Solana USD", market: "crypto", marketLabel: "Crypto", price: "186.42", change: "-1.24%" },
    ],
  },
};

function ListsDemo({ language }: { language: Language }) {
  const text = copy[language].lists;
  const listRows = listRowsByLanguage[language];
  const [activeList, setActiveList] = useState<DemoListId>("core");

  return (
    <div className="feature-demo lists-demo" data-testid="lists-demo">
      <div className="lists-controls">
        <div className="lists-tabs" role="tablist" aria-label={text.tabsLabel}>
          {demoLists.map((list) => (
            <button
              key={list.id}
              type="button"
              role="tab"
              aria-selected={activeList === list.id}
              className={activeList === list.id ? "active" : undefined}
              onClick={() => setActiveList(list.id)}
            >
              {list.label[language]}
            </button>
          ))}
        </div>
        <span className="lists-hint">{text.hint}</span>
      </div>
      <ul className="positions-list preview-panel-enter" key={activeList}>
        {listRows[activeList].map((row) => {
          const positive = row.change.startsWith("+");
          return (
            <li key={row.symbol}>
              <span className="position-row-title">
                <strong>{row.name}</strong>
                <span>
                  <span className={`preview-market preview-market-${row.market}`}>
                    {row.marketLabel}
                  </span>
                  {row.symbol}
                </span>
              </span>
              <span className="list-row-value">
                <strong>{row.price}</strong>
                <span className={positive ? "positive" : "negative"}>
                  {row.change}
                </span>
              </span>
            </li>
          );
        })}
      </ul>
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

        <article className="feature-card feature-card--positions">
          <div className="feature-card-copy">
            <h3>{text.positions.title}</h3>
            <p>{text.positions.description}</p>
          </div>
          <PositionsDemo language={language} />
        </article>

        <article className="feature-card feature-card--lists">
          <div className="feature-card-copy">
            <h3>{text.lists.title}</h3>
            <p>{text.lists.description}</p>
          </div>
          <ListsDemo language={language} />
        </article>
      </div>
    </section>
  );
}
