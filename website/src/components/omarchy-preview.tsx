import { PulseWordmark } from "./pulse-wordmark";

type OmarchyMarketItem = {
  name: string;
  symbol: string;
  market: string;
  price: string;
  change: string;
  positive: boolean;
  points: string;
};

const omarchyMarketItems: OmarchyMarketItem[] = [
  {
    name: "Tencent Holdings",
    symbol: "700",
    market: "HK",
    price: "451.40",
    change: "+0.94%",
    positive: true,
    points: "0,31 10,28 18,30 27,24 38,25 48,21 59,23 69,18 80,19 92,14 104,15 115,12 126,17 138,15 150,18 162,17 174,22 186,20 198,25 210,23 222,28",
  },
  {
    name: "Hang Seng Index",
    symbol: "HSI",
    market: "HK",
    price: "25,698.49",
    change: "+0.89%",
    positive: true,
    points: "0,20 9,14 18,25 28,29 38,31 49,28 60,29 70,26 81,19 92,17 103,18 114,15 125,17 136,14 148,13 160,16 171,18 182,19 194,23 206,22 218,27 222,27",
  },
  {
    name: "Kweichow Moutai",
    symbol: "600519",
    market: "CN",
    price: "1,291.50",
    change: "-1.25%",
    positive: false,
    points: "0,11 10,15 20,28 30,32 40,27 51,34 62,36 73,31 84,39 95,35 106,39 117,31 128,39 139,37 150,39 162,34 174,37 186,35 198,38 210,37 222,39",
  },
  {
    name: "SSE Composite Index",
    symbol: "000001",
    market: "CN",
    price: "3,903.72",
    change: "-2.17%",
    positive: false,
    points: "0,27 12,24 24,26 36,29 48,28 60,31 72,32 84,30 96,34 108,33 120,36 132,35 144,37 156,36 168,38 180,37 192,35 204,36 216,34 222,35",
  },
  {
    name: "Toyota Motor Corp.",
    symbol: "7203",
    market: "JP",
    price: "3,104.00",
    change: "+1.24%",
    positive: true,
    points: "0,24 18,23 34,22 50,26 66,30 82,31 98,29 114,27 130,25 146,23 162,22 178,22 194,21 210,22 222,21",
  },
  {
    name: "Samsung Electronics",
    symbol: "005930",
    market: "KR",
    price: "271,500.00",
    change: "+0.18%",
    positive: true,
    points: "0,37 16,32 32,27 48,17 64,29 80,36 96,36 112,35 128,33 144,31 160,29 176,27 192,25 208,22 222,20",
  },
  {
    name: "Amazon.com, Inc.",
    symbol: "AMZN",
    market: "US",
    price: "260.52",
    change: "+0.16%",
    positive: true,
    points: "0,18 10,20 20,17 30,22 40,21 50,25 60,24 70,29 80,27 90,31 100,30 110,34 120,32 130,35 140,33 150,36 160,34 170,37 180,35 190,36 200,34 212,35 222,33",
  },
  {
    name: "Apple Inc.",
    symbol: "AAPL",
    market: "US",
    price: "312.10",
    change: "+0.26%",
    positive: true,
    points: "0,24 10,22 20,26 30,23 40,25 50,20 60,24 70,18 80,19 90,17 100,20 110,21 120,18 130,22 140,20 150,30 160,32 170,31 180,29 190,28 200,27 212,28 222,26",
  },
  {
    name: "NVIDIA Corporation",
    symbol: "NVDA",
    market: "US",
    price: "217.05",
    change: "+0.09%",
    positive: true,
    points: "0,27 12,29 24,28 36,30 48,28 60,29 72,23 84,27 96,30 108,26 120,29 132,25 144,28 156,26 168,27 180,26 192,27 204,26 216,27 222,27",
  },
  {
    name: "S&P 500",
    symbol: "SPX",
    market: "US",
    price: "7,641.16",
    change: "+0.00%",
    positive: true,
    points: "0,13 12,12 24,16 36,15 48,19 60,18 72,22 84,21 96,25 108,24 120,28 132,27 144,31 156,30 168,34 180,33 192,36 204,35 216,39 222,39",
  },
];

function PreviewIcon({ name }: { name: "search" | "edit" | "settings" }) {
  if (name === "search") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M9.5 3A6.5 6.5 0 0 1 16 9.5c0 1.61-.59 3.09-1.56 4.23l.27.27h.79l5 5-1.5 1.5-5-5v-.79l-.27-.27A6.5 6.5 0 1 1 9.5 3Zm0 2A4.5 4.5 0 1 0 14 9.5 4.5 4.5 0 0 0 9.5 5Z" />
      </svg>
    );
  }

  if (name === "edit") {
    return (
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.84 1.83 3.75 3.75M3 17.25V21h3.75L17.81 9.93l-3.75-3.75L3 17.25Z" />
      </svg>
    );
  }

  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7Zm7.43-2.53c.04-.32.07-.64.07-.97s-.03-.66-.07-1l2.11-1.63a.5.5 0 0 0 .12-.64l-2-3.46a.5.5 0 0 0-.61-.22l-2.49 1a7.53 7.53 0 0 0-1.69-.98l-.37-2.65A.5.5 0 0 0 14 2h-4a.5.5 0 0 0-.5.42l-.37 2.65c-.63.25-1.17.59-1.69.98l-2.49-1a.5.5 0 0 0-.61.22l-2 3.46a.5.5 0 0 0 .12.64L4.57 11c-.04.34-.07.67-.07 1s.03.65.07.97l-2.11 1.66a.5.5 0 0 0-.12.64l2 3.46a.5.5 0 0 0 .61.22l2.49-1.01c.52.4 1.06.74 1.69.99l.37 2.65a.5.5 0 0 0 .5.42h4a.5.5 0 0 0 .5-.42l.37-2.65c.63-.26 1.17-.59 1.69-.99l2.49 1.01a.5.5 0 0 0 .61-.22l2-3.46a.5.5 0 0 0-.12-.64l-2.11-1.66Z" />
    </svg>
  );
}

function OmarchyTrend({ item }: { item: OmarchyMarketItem }) {
  return (
    <svg
      className={`omarchy-trend ${item.positive ? "is-positive" : "is-negative"}`}
      viewBox="0 0 222 48"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <line x1="0" y1="38" x2="222" y2="38" />
      <polyline points={item.points} />
    </svg>
  );
}

export function OmarchyPreview({ ariaLabel }: { ariaLabel: string }) {
  return (
    <div className="omarchy-preview" role="img" aria-label={ariaLabel}>
      <div className="omarchy-preview-header" aria-hidden="true">
        <PulseWordmark className="omarchy-preview-brand" />
        <div className="omarchy-preview-tools">
          <PreviewIcon name="search" />
          <PreviewIcon name="edit" />
          <PreviewIcon name="settings" />
        </div>
      </div>

      <div className="omarchy-preview-tabs" aria-hidden="true">
        <span>Watching</span>
        <b>+</b>
      </div>

      <div className="omarchy-preview-list" aria-hidden="true">
        {omarchyMarketItems.map((item) => (
          <div className="omarchy-preview-row" key={item.symbol}>
            <div className="omarchy-preview-name">
              <strong>{item.name}</strong>
              <span>
                <b>{item.market}</b>
                {item.symbol}
              </span>
            </div>
            <OmarchyTrend item={item} />
            <div className="omarchy-preview-value">
              <strong>{item.price}</strong>
              <span className={item.positive ? "is-positive" : "is-negative"}>
                {item.change}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div className="omarchy-preview-footer" aria-hidden="true">
        <span><i />LIVE</span>
        <span>{omarchyMarketItems.length} symbols</span>
      </div>
    </div>
  );
}
