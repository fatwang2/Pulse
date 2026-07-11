"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";

type Language = "zh" | "en";
type MetricMode = "change" | "today" | "total";

type MarketItem = {
  symbol: string;
  name: string;
  market: "US" | "SH" | "HK" | "Crypto";
  price: string;
  change: string;
  today: string;
  total: string;
  positive: boolean;
  series: number[];
};

const marketItems: MarketItem[] = [
  {
    symbol: "ONDS",
    name: "Ondas Inc.",
    market: "US",
    price: "7.67",
    change: "+0.26%",
    today: "+$12.40",
    total: "+$184.70",
    positive: true,
    series: [72, 68, 73, 70, 71, 69, 74, 55, 64, 57, 52, 58, 49, 57, 57, 69, 67, 91, 94, 88, 98, 91, 95, 89, 94, 87, 92, 88, 82, 79, 72, 75, 68, 44, 47, 46, 20, 22],
  },
  {
    symbol: "601138",
    name: "工业富联",
    market: "SH",
    price: "68.40",
    change: "-1.63%",
    today: "-¥326.00",
    total: "+¥2,184",
    positive: false,
    series: [82, 99, 87, 60, 72, 61, 51, 43, 37, 31, 44, 38, 50, 39, 41, 38, 35, 34, 36, 42, 34, 36, 33, 31, 35, 30, 39],
  },
  {
    symbol: "688018",
    name: "乐鑫科技",
    market: "SH",
    price: "129.39",
    change: "+6.67%",
    today: "+¥1,624",
    total: "+¥8,960",
    positive: true,
    series: [34, 38, 48, 48, 66, 55, 48, 44, 40, 35, 61, 66, 71, 74, 65, 70, 67, 64, 62, 60, 69, 63, 63, 61, 64, 68, 64, 65],
  },
  {
    symbol: "603986",
    name: "兆易创新",
    market: "SH",
    price: "663.38",
    change: "-0.02%",
    today: "-¥42.00",
    total: "+¥4,106",
    positive: false,
    series: [77, 78, 75, 77, 80, 71, 59, 53, 44, 57, 48, 51, 39, 35, 42, 33, 32, 43, 32, 34, 34, 33, 23, 20, 27],
  },
  {
    symbol: "700",
    name: "腾讯控股",
    market: "HK",
    price: "468.00",
    change: "-0.34%",
    today: "-HK$136",
    total: "+HK$6,240",
    positive: false,
    series: [41, 30, 27, 51, 75, 54, 43, 36, 66, 55, 57, 45, 48, 51, 45, 68, 70, 47, 52, 62, 63, 61, 58],
  },
  {
    symbol: "6181",
    name: "老铺黄金",
    market: "HK",
    price: "392.60",
    change: "+2.51%",
    today: "+HK$964",
    total: "+HK$12,760",
    positive: true,
    series: [44, 28, 26, 39, 35, 42, 45, 47, 50, 53, 55, 55, 51, 56, 52, 58, 69, 67, 87, 89, 94, 92, 86, 88],
  },
  {
    symbol: "BTC-USD",
    name: "Bitcoin USD",
    market: "Crypto",
    price: "63797.28",
    change: "+0.97%",
    today: "+$187.20",
    total: "+$3,482",
    positive: true,
    series: [27, 28, 25, 16, 22, 17, 20, 14, 21, 19, 26, 39, 45, 49, 44, 50, 52, 73, 82, 77, 80, 78, 84, 89, 88, 85, 82, 86, 82, 84, 80, 79],
  },
];

const copy = {
  zh: {
    tagline: "你的市场，一眼掌握。",
    modes: { change: "涨跌幅", today: "今日盈亏", total: "持仓盈亏" },
    modeAction: "切换列表指标，当前为",
    updated: "刚刚更新",
    reference: "静态演示数据",
  },
  en: {
    tagline: "Your market, at a glance.",
    modes: { change: "Change", today: "Today P&L", total: "Position P&L" },
    modeAction: "Change list metric, currently",
    updated: "Updated just now",
    reference: "Static demo data",
  },
} as const;

const modeOrder: MetricMode[] = ["change", "today", "total"];

function lineColor(positive: boolean) {
  return positive ? "#ff414b" : "#00a962";
}

function canvasSize(canvas: HTMLCanvasElement) {
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

function pointCoordinates(series: number[], width: number, height: number) {
  const minimum = Math.min(...series);
  const maximum = Math.max(...series);
  const spread = Math.max(1, maximum - minimum);
  const inset = width < 150 ? 2 : 4;

  return series.map((value, index) => ({
    x: inset + (index / Math.max(1, series.length - 1)) * (width - inset * 2),
    y: inset + ((maximum - value) / spread) * (height - inset * 2),
  }));
}

function drawLine(
  context: CanvasRenderingContext2D,
  points: { x: number; y: number }[],
  color: string,
  height: number,
  progress = 1,
) {
  const visibleCount = Math.max(2, Math.ceil(points.length * progress));
  const visible = points.slice(0, visibleCount);

  context.beginPath();
  visible.forEach((point, index) => {
    if (index === 0) context.moveTo(point.x, point.y);
    else context.lineTo(point.x, point.y);
  });
  context.lineTo(visible[visible.length - 1].x, height - 2);
  context.lineTo(visible[0].x, height - 2);
  context.closePath();
  context.fillStyle = `${color}10`;
  context.fill();

  context.beginPath();
  visible.forEach((point, index) => {
    if (index === 0) context.moveTo(point.x, point.y);
    else context.lineTo(point.x, point.y);
  });
  context.strokeStyle = color;
  context.lineWidth = 1.35;
  context.lineCap = "round";
  context.lineJoin = "round";
  context.stroke();
}

function Sparkline({ item, active }: { item: MarketItem; active: boolean }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let animationFrame = 0;
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const startedAt = performance.now();

    function render(now: number) {
      if (!canvas) return;
      const { context, width, height } = canvasSize(canvas);
      if (!context) return;
      context.clearRect(0, 0, width, height);
      context.setLineDash([3, 3]);
      context.strokeStyle = "rgba(120, 128, 138, 0.2)";
      context.lineWidth = 0.75;
      context.beginPath();
      context.moveTo(0, height * 0.62);
      context.lineTo(width, height * 0.62);
      context.stroke();
      context.setLineDash([]);

      const duration = active && !reducedMotion ? 430 : 0;
      const progress = duration === 0 ? 1 : Math.min(1, (now - startedAt) / duration);
      const points = pointCoordinates(item.series, width, height);
      drawLine(context, points, lineColor(item.positive), height, progress);

      if (active && progress === 1) {
        const end = points[points.length - 1];
        context.beginPath();
        context.arc(end.x, end.y, 2.6, 0, Math.PI * 2);
        context.fillStyle = lineColor(item.positive);
        context.fill();
        context.beginPath();
        context.arc(end.x, end.y, 5.5, 0, Math.PI * 2);
        context.strokeStyle = `${lineColor(item.positive)}42`;
        context.lineWidth = 1;
        context.stroke();
      }

      if (progress < 1) animationFrame = requestAnimationFrame(render);
    }

    animationFrame = requestAnimationFrame(render);
    return () => cancelAnimationFrame(animationFrame);
  }, [active, item]);

  return (
    <canvas
      ref={canvasRef}
      className="preview-sparkline"
      aria-label={`${item.name} ${item.change}`}
      role="img"
    />
  );
}

function MarketBadge({ market }: { market: MarketItem["market"] }) {
  return <span className={`preview-market preview-market-${market.toLowerCase()}`}>{market}</span>;
}

export function InteractivePreview({
  language,
  ariaLabel,
}: {
  language: Language;
  ariaLabel: string;
}) {
  const text = copy[language];
  const [mode, setMode] = useState<MetricMode>("change");
  const [hoveredSymbol, setHoveredSymbol] = useState<string | null>(null);

  function cycleMode() {
    setMode((current) => modeOrder[(modeOrder.indexOf(current) + 1) % modeOrder.length]);
  }

  return (
    <div
      className="interactive-preview"
      data-testid="interactive-preview"
      aria-label={ariaLabel}
    >
      <section className="preview-watchlist preview-panel-enter" aria-label={ariaLabel}>
          <header className="preview-app-header">
            <div className="preview-app-identity">
              <Image
                src="/pulse-icon.png"
                alt=""
                width={44}
                height={44}
                unoptimized
              />
              <div><strong>Pulse</strong><span>{text.tagline}</span></div>
            </div>
          </header>

          <ul className="preview-list">
            {marketItems.map((item) => {
              const active = hoveredSymbol === item.symbol;
              const metric = mode === "change" ? item.change : mode === "today" ? item.today : item.total;
              return (
                <li
                  className="preview-row"
                  key={item.symbol}
                  onPointerEnter={() => setHoveredSymbol(item.symbol)}
                  onPointerLeave={() => setHoveredSymbol(null)}
                >
                  <span className="preview-row-title">
                    <strong>{item.name}</strong>
                    <span><MarketBadge market={item.market} />{item.symbol}</span>
                  </span>
                  <Sparkline item={item} active={active} />
                  <button
                    className="preview-row-value"
                    type="button"
                    aria-label={`${text.modeAction} ${text.modes[mode]}: ${item.name}, ${item.price}, ${metric}`}
                    onFocus={() => setHoveredSymbol(item.symbol)}
                    onBlur={() => setHoveredSymbol(null)}
                    onClick={(event) => {
                      cycleMode();
                      if (event.detail > 0) event.currentTarget.blur();
                    }}
                  >
                    <strong>{item.price}</strong>
                    <span key={`${item.symbol}-${mode}`} className={`preview-metric ${item.positive ? "positive" : "negative"}`}>
                      {metric}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>

          <footer className="preview-app-footer">
            <span>{text.updated}</span>
            <span>{text.reference}</span>
          </footer>
          <span className="sr-only" aria-live="polite">{text.modes[mode]}</span>
        </section>
    </div>
  );
}
