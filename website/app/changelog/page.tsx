"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { releases } from "./releases";

type Language = "zh" | "en";

const repositoryReleasesUrl = "https://github.com/fatwang2/Pulse/releases";

const translations = {
  zh: {
    homeLabel: "Pulse 首页",
    home: "首页",
    changelog: "更新日志",
    languageLabel: "切换网站语言",
    overline: "版本时间线",
    title: "每一次更新，\n都清楚可见。",
    intro:
      "从首次公开发布到最新版本，按时间查看 Pulse 的新功能、体验改进与问题修复。",
    latest: "最新版",
    release: "新版本",
    improvement: "体验改进",
    fix: "问题修复",
    viewRelease: "在 GitHub 查看",
    allReleases: "查看全部 GitHub Releases",
    download: "下载最新版",
    pageTitle: "Pulse 更新日志 — 每一次更新都清楚可见",
  },
  en: {
    homeLabel: "Pulse home",
    home: "Home",
    changelog: "Changelog",
    languageLabel: "Change website language",
    overline: "Release timeline",
    title: "Every release,\nat a glance.",
    intro:
      "Follow Pulse from its first public release to today, with every new feature, experience improvement, and fix in one place.",
    latest: "Latest",
    release: "New release",
    improvement: "Improvement",
    fix: "Fix",
    viewRelease: "View on GitHub",
    allReleases: "View all GitHub Releases",
    download: "Download latest",
    pageTitle: "Pulse Changelog — Every release at a glance",
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

export default function Changelog() {
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
    <main className="changelog-page">
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
            <Link href="/">{copy.home}</Link>
            <Link href="/changelog" aria-current="page">
              {copy.changelog}
            </Link>
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

      <section className="changelog-hero shell">
        <p className="overline">{copy.overline}</p>
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
            <li className="release-entry" key={release.version}>
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
                    <h2>Pulse {release.version}</h2>
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
                <a
                  className="release-link"
                  href={`${repositoryReleasesUrl}/tag/v${release.version}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {copy.viewRelease}
                  <span aria-hidden="true">↗</span>
                </a>
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
          <Image src="/apple.svg" alt="" width={15} height={15} aria-hidden="true" />
          {copy.download}
        </a>
      </footer>
    </main>
  );
}
