import { Link } from "@tanstack/react-router";
import { releases } from "../data/releases";

type Language = "zh" | "en";

const copy = {
  zh: {
    title: "最近更新",
    all: "全部更新",
    latest: "最新版",
  },
  en: {
    title: "Recent updates",
    all: "All releases",
    latest: "Latest",
  },
} as const;

function formatDate(date: string, language: Language) {
  const [year, month, day] = date.split("-").map(Number);
  return new Intl.DateTimeFormat(language === "zh" ? "zh-CN" : "en-US", {
    year: "numeric",
    month: language === "zh" ? "long" : "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

export function RecentUpdates({ language }: { language: Language }) {
  const text = copy[language];
  const latest = releases.slice(0, 2);

  return (
    <section
      className="recent-updates shell"
      aria-labelledby="recent-updates-title"
      data-testid="recent-updates"
    >
      <div className="recent-updates-heading">
        <h2 id="recent-updates-title">{text.title}</h2>
        <Link to="/changelog">
          {text.all}
          <span aria-hidden="true">→</span>
        </Link>
      </div>
      <ol>
        {latest.map((release, index) => (
          <li key={release.version}>
            <div className="recent-update-meta">
              <strong>{`Pulse ${release.version}`}</strong>
              <time dateTime={release.date}>
                {formatDate(release.date, language)}
              </time>
              {index === 0 ? (
                <span className="latest-badge">{text.latest}</span>
              ) : null}
            </div>
            <p>{release.highlights[language][0]}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
