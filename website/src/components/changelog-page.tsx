import { SiteHeader } from "./site-header";
import { releases } from "../data/releases";
import type { Language } from "../i18n";

const repositoryReleasesUrl = "https://github.com/fatwang2/Pulse/releases";

const translations = {
  zh: {
    title: "每一次更新，\n都清楚可见。",
    intro:
      "从首次公开发布到最新版本，按时间查看 Pulse 的新功能、体验改进与问题修复。",
    latest: "最新版",
    release: "新版本",
    improvement: "体验改进",
    fix: "问题修复",
    releaseAnchor: "链接到版本",
    allReleases: "查看全部 GitHub Releases",
    download: "下载最新版",
    changelog: "更新日志",
  },
  en: {
    title: "Every release,\nat a glance.",
    intro:
      "Follow Pulse from its first public release to today, with every new feature, experience improvement, and fix in one place.",
    latest: "Latest",
    release: "New release",
    improvement: "Improvement",
    fix: "Fix",
    releaseAnchor: "Link to release",
    allReleases: "View all GitHub Releases",
    download: "Download latest",
    changelog: "Changelog",
  },
  ja: {
    title: "すべてのリリースを、\nひと目で。",
    intro:
      "初回公開から最新バージョンまで、Pulse の新機能・改善・修正を時系列でたどれます。",
    latest: "最新",
    release: "新リリース",
    improvement: "改善",
    fix: "修正",
    releaseAnchor: "リリースへのリンク",
    allReleases: "GitHub Releases をすべて見る",
    download: "最新版をダウンロード",
    changelog: "更新履歴",
  },
  ko: {
    title: "모든 릴리스를,\n한눈에.",
    intro:
      "첫 공개부터 오늘까지, Pulse의 새 기능과 개선, 수정 사항을 한곳에서 시간순으로 볼 수 있습니다.",
    latest: "최신",
    release: "새 릴리스",
    improvement: "개선",
    fix: "수정",
    releaseAnchor: "이 릴리스로 이동",
    allReleases: "GitHub Releases 전체 보기",
    download: "최신 버전 다운로드",
    changelog: "업데이트 내역",
  },
} as const;

const dateLocales: Record<Language, string> = {
  zh: "zh-CN",
  en: "en-US",
  ja: "ja-JP",
  ko: "ko-KR",
};

function formatDate(date: string, language: Language) {
  const [year, month, day] = date.split("-").map(Number);
  return new Intl.DateTimeFormat(dateLocales[language], {
    year: "numeric",
    month: language === "en" ? "short" : "long",
    day: "numeric",
    timeZone: "UTC",
  }).format(new Date(Date.UTC(year, month - 1, day)));
}

export function ChangelogPage({ language }: { language: Language }) {
  const copy = translations[language];

  return (
    <main className="changelog-page">
      <SiteHeader language={language} page="changelog" />

      <section className="changelog-hero shell">
        <h1>
          {copy.title.split("\n").map((line, index) => (
            <span key={line}>
              {line}
              {index === 0 ? <br /> : null}
            </span>
          ))}
        </h1>
        <p>{copy.intro}</p>
      </section>

      <section className="changelog-content shell" aria-label={copy.changelog}>
        <ol className="release-timeline" data-testid="release-timeline">
          {releases.map((release, index) => (
            <li
              className="release-entry"
              id={`v${release.version.replaceAll(".", "-")}`}
              key={release.version}
            >
              <div className="release-meta">
                <time dateTime={release.date}>
                  {formatDate(release.date, language)}
                </time>
              </div>
              <div
                className={`release-marker${index === 0 ? " release-marker--latest" : ""}`}
                aria-hidden="true"
              />
              <article className="release-card">
                <header className="release-heading">
                  <div className="release-title">
                    <h2>
                      <a
                        className="release-anchor"
                        href={`#v${release.version.replaceAll(".", "-")}`}
                        aria-label={`${copy.releaseAnchor} ${release.version}`}
                      >
                        Pulse {release.version}
                        <span aria-hidden="true">#</span>
                      </a>
                    </h2>
                    {index === 0 ? (
                      <span className="latest-badge">{copy.latest}</span>
                    ) : null}
                  </div>
                  <span className={`release-kind release-kind--${release.kind}`}>
                    {copy[release.kind]}
                  </span>
                </header>
                <time className="release-mobile-date" dateTime={release.date}>
                  {formatDate(release.date, language)}
                </time>
                <ul className="release-highlights">
                  {release.highlights[language].map((highlight) => (
                    <li key={highlight}>{highlight}</li>
                  ))}
                </ul>
              </article>
            </li>
          ))}
        </ol>
      </section>

      <footer className="changelog-footer shell">
        <a href={repositoryReleasesUrl} target="_blank" rel="noreferrer">
          {copy.allReleases}
          <span aria-hidden="true">↗</span>
        </a>
        <a className="cta-button cta-primary" href="/download">
          <img src="/apple.svg" alt="" width={15} height={15} aria-hidden="true" />
          {copy.download}
        </a>
      </footer>
    </main>
  );
}
